# app/controllers/api/devices_controller.rb
class Api::DevicesController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!, raise: false
  before_action :authenticate_api_user!, only: [:register]
  before_action :authenticate_device!, only: [:connect, :disconnect, :heartbeat, :credentials]

  # POST api/devices/register
  def register
    subscription = @current_api_user.subscriptions.last

    unless subscription
      render json: {
        error: "No subscription found",
        message: "You need to purchase a subscription first.",
        action_required: "subscribe",
        renewal_url: "https://www.vulcainvpn.com/dashboard/"
      }, status: :forbidden
      return
    end

    # Find or create device
    device = Device.find_by(device_id: params[:device_id])

    if device
      # Device exists - link it to current subscription if different
      if device.subscription_id != subscription.id
        Rails.logger.info "🔄 Auto-linking device #{device.device_id} to subscription #{subscription.id}"
        device.update!(subscription: subscription, active: false)
      end
    else
      # Create new device
      device = subscription.devices.new(device_id: params[:device_id])
    end

    device.assign_attributes(
      user: @current_api_user,
      platform: params[:platform],
      name: params[:name]
    )

    if device.save
      render json: {
        api_key: device.api_key,
        device_id: device.device_id,
        message: "Device registered successfully"
      }, status: :created
    else
      render json: { error: device.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  # POST api/connect/:device_id
  def connect
    subscription = current_subscription
    device = current_device

    # ⭐ STEP 1: Release any existing config (in_use OR used)
    existing_config = device.vpn_config_set

    if existing_config
      Rails.logger.info "Device #{device.id} releasing config #{existing_config.ip_address} (was: #{existing_config.status})"
      existing_config.release!

      # Close any active connection records
      device.vpn_connections.where(disconnected_at: nil).update_all(
        disconnected_at: Time.current
      )
    end

    # Reset device state before new connection
    device.update!(active: false, connected_at: nil)

    # ⭐ STEP 2: Check device limit (excluding current device)
    active_count = subscription.devices
                              .where(active: true)
                              .where.not(id: device.id)
                              .count

    if active_count >= subscription.max_devices
      render json: {
        error: "Maximum active devices reached",
        message: "You can only have #{subscription.max_devices} devices connected simultaneously.",
        max_devices: subscription.max_devices,
        active_devices: active_count,
        action_required: "disconnect_device"
      }, status: :too_many_requests
      return
    end

    # ⭐ STEP 3: Find best server
    selector = ServerSelectorService.new
    server = selector.find_best_server(
      user_ip: request.remote_ip,
      preferred_location: params[:preferred_location]
    )

    unless server
      render json: {
        error: "No servers available",
        message: "All servers are currently at capacity."
      }, status: :service_unavailable
      return
    end

    # ⭐ STEP 4: Claim fresh config from pool
    config_set = nil

    VpnConfigSet.transaction do
      config_set = VpnConfigSet.where(server: server, status: 'available')
                              .lock('FOR UPDATE SKIP LOCKED')
                              .first

      if config_set
        config_set.claim!(device)
      end
    end

    unless config_set
      render json: {
        error: "Server at capacity",
        message: "Selected server is currently full.",
        retry: true
      }, status: :service_unavailable
      return
    end

    # ⭐ STEP 5: Create connection record
    VpnConnection.create!(
      user: device.user,
      device: device,
      config_set: config_set,
      server: server,
      connected_at: Time.current
    )

    # ⭐ STEP 6: Update device status
    device.update!(
      active: true,
      connected_at: Time.current,
      last_seen_at: Time.current,
      last_connection_ip: request.remote_ip
    )

    # ⭐ STEP 7: Build and return credentials
    credentials = build_credentials_from_config(config_set)

    render json: {
      message: "Connected successfully",
      server: {
        name: server.name,
        location: server.location || server.city,
        country: server.country_code
      },
      credentials: credentials
    }, status: :ok

  rescue => e
    Rails.logger.error "Connection failed for device #{device.id}: #{e.message}"
    render json: {
      error: "Connection failed",
      message: "An error occurred while connecting."
    }, status: :internal_server_error
  end

  # POST api/disconnect/:device_id
  def disconnect
    device = current_device

    # Release config back to pool
    config_set = device.vpn_config_set
    if config_set
      config_set.release!
      Rails.logger.info "Released config #{config_set.ip_address} from device #{device.id}"
    end

    # Close active connection
    active_connection = device.vpn_connections.active.last
    active_connection&.update!(disconnected_at: Time.current)

    # Mark device as inactive
    device.update!(active: false, connected_at: nil)

    render json: { message: "Disconnected successfully" }, status: :ok
  end

  # GET api/credentials/:device_id
  def credentials
    device = current_device
    config_set = device.vpn_config_set

    unless config_set
      render json: {
        error: "Not connected",
        message: "Device is not connected to VPN"
      }, status: :not_found
      return
    end

    render json: {
      credentials: build_credentials_from_config(config_set)
    }, status: :ok
  end

  # POST api/heartbeat/:device_id
  def heartbeat
    device = current_device
    subscription = device.subscription

    # ✅ CHECK SUBSCRIPTION BEFORE ACCEPTING HEARTBEAT
    unless subscription && subscription.active?
      render json: {
        status: "subscription_expired",
        subscription_active: false,
        subscription_status: subscription&.status,
        expires_at: subscription&.expires_at,
        message: "Your subscription has expired",
        action_required: "renew"
      }, status: 403
      return
    end

    # ✅ Only update last_seen_at if subscription is valid
    device.update!(
      last_seen_at: Time.current,
      last_connection_ip: request.remote_ip
    )

    render json: {
      status: "alive",
      subscription_active: true
    }, status: :ok
  end

  private

  def authenticate_api_user!
    token = request.headers['Authorization']&.split(' ')&.last

    unless token.present?
      render json: { error: "Authorization token required" }, status: :unauthorized
      return
    end

    begin
      payload = JWT.decode(
        token,
        ENV['DEVISE_JWT_SECRET_KEY'],
        true,
        algorithm: 'HS256'
      ).first

      if JwtDenylist.exists?(jti: payload['jti'])
        render json: { error: "Token has been revoked" }, status: :unauthorized
        return
      end

      @current_api_user = User.find(payload['sub'])

    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render json: { error: "Invalid or expired token" }, status: :unauthorized
    end
  end

  def authenticate_device!
    api_key = request.headers['X-Api-Key']

    unless api_key.present?
      render json: {
        error: "API key required",
        message: "Device not registered. Please login again."
      }, status: :unauthorized
      return
    end

    @current_device = Device.find_by(api_key: api_key)

    unless @current_device
      render json: {
        error: "Invalid API key",
        message: "Device not registered. Please login again."
      }, status: :unauthorized
      return
    end

    # Check subscription status
    current_subscription = @current_device.subscription

    unless current_subscription.active?
      # Try to auto-link to active subscription
      active_subscription = @current_device.user.subscriptions.active.first

      if active_subscription
        Rails.logger.info "🔄 Auto-linking device to active subscription"
        @current_device.update!(subscription: active_subscription, active: false)
        @current_device.reload
      else
        render json: {
          error: "No active subscription",
          message: "Your subscription has expired. Please renew to continue.",
          subscription_status: current_subscription.status,
          expires_at: current_subscription.expires_at,
          action_required: "renew",
          renewal_url: "https://www.vulcainvpn.com/dashboard/"
        }, status: :forbidden
        return
      end
    end
  end

  def current_device
    @current_device
  end

  def current_subscription
    @current_device.subscription
  end

  # ⭐ NEW: Build credentials from config set
  def build_credentials_from_config(config_set)
    server = config_set.server

    credentials = {
      wireguard: {
        server_ip: server.ip_address,
        server_port: server.wireguard_port,
        server_public_key: server.wireguard_public_key,
        client_private_key: config_set.wireguard_private_key,
        client_public_key: config_set.wireguard_public_key,
        client_preshared_key: config_set.wireguard_preshared_key,
        client_ip: config_set.ip_address
      }
    }

    # Add sing-box protocols if enabled
    if server.singbox_active?
      credentials[:hysteria2] = {
        server: server.singbox_server_name,
        port: server.singbox_hysteria2_port,
        password: config_set.hysteria2_password,
        obfs_type: "salamander",
        obfs_password: server.singbox_salamander_password,
        tls_server_name: server.singbox_server_name
      }

      credentials[:shadowsocks] = {
        server: server.ip_address,
        port: server.singbox_ss_port,
        method: "2022-blake3-aes-256-gcm",
        password: "#{server.singbox_ss_master_password}:#{config_set.shadowsocks_password}"
      }
    end

    credentials
  end
end
