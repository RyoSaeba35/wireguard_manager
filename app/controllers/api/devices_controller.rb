# app/controllers/api/devices_controller.rb
class Api::DevicesController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!, raise: false
  before_action :authenticate_api_user!, only: [:register]
  before_action :authenticate_device!, only: [:connect, :disconnect, :heartbeat, :credentials]

  MAX_DEVICES = 3

  # POST api/devices/register
  # ✅ CHANGED: Allow registration even without active subscription
  # Device stays registered, but can't connect without subscription
  def register
    # ✅ Look for ANY subscription (active or not)
    subscription = @current_api_user.subscriptions.last

    unless subscription
      # User has never had a subscription
      render json: {
        error: "No subscription found",
        message: "You need to purchase a subscription first.",
        action_required: "subscribe",
        renewal_url: "https://vulcainvpn.com/pricing"
      }, status: :forbidden
      return
    end

    # ✅ Allow registration even if subscription is expired
    # Just use the most recent subscription (active or not)

    # Look for device ANYWHERE first (not scoped to subscription)
    device = Device.find_by(device_id: params[:device_id])

    if device
      # Device exists - link it to the current subscription
      if device.subscription_id != subscription.id
        Rails.logger.info "🔄 Auto-linking existing device #{device.device_id} from subscription #{device.subscription_id} to subscription #{subscription.id}"
        device.update!(subscription: subscription, active: false)
      end
    else
      # Device doesn't exist - create new one
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
  # ✅ Check order: Subscription (via before_action) → Device Limit → Assign Credentials
  def connect
    subscription = current_subscription
    device = current_device

    # Subscription is already checked in authenticate_device! before_action
    # If we're here, subscription is active

    # ✅ STEP 2: Check active device limit
    active_count = subscription.devices
                                .where(active: true)
                                .where.not(id: device.id)
                                .count

    if active_count >= MAX_DEVICES
      render json: {
        error: "Maximum active devices reached",
        message: "You can only have #{MAX_DEVICES} devices connected simultaneously. Please disconnect another device first.",
        max_devices: MAX_DEVICES,
        active_devices: active_count,
        action_required: "disconnect_device"
      }, status: :too_many_requests  # 429
      return
    end

    # ✅ STEP 3: Check if WireGuard slots available
    available_wg_client = subscription.wireguard_clients.where(device_id: nil).exists?
    already_has_wg = subscription.wireguard_clients.exists?(device_id: device.id)

    unless available_wg_client || already_has_wg
      render json: {
        error: "Maximum active devices reached",
        message: "All WireGuard connection slots are in use. Please disconnect another device first.",
        action_required: "disconnect_device"
      }, status: :too_many_requests  # 429
      return
    end

    # ✅ STEP 4: Mark device as active and assign credentials
    device.update!(
      active: true,
      connected_at: Time.current,
      last_seen_at: Time.current,
      last_connection_ip: request.remote_ip
    )

    # ✅ STEP 5: Build and return credentials (with assignment)
    credentials = build_credentials(device, assign: true)

    # Double-check that WireGuard credentials were successfully assigned
    unless credentials[:wireguard].present?
      device.update!(active: false, connected_at: nil)
      render json: {
        error: "Maximum active devices reached",
        message: "Failed to assign connection credentials. Please try again or disconnect another device.",
        action_required: "disconnect_device"
      }, status: :too_many_requests
      return
    end

    render json: {
      message: "Connected successfully",
      credentials: credentials
    }, status: :ok
  end

  # POST api/disconnect/:device_id
  def disconnect
    device = current_device
    subscription = device.subscription

    # Free all protocol clients back to the pool
    subscription.wireguard_clients.where(device_id: device.id).update_all(device_id: nil)
    subscription.hysteria2_clients.where(device_id: device.id).update_all(device_id: nil)
    subscription.shadowsocks_clients.where(device_id: device.id).update_all(device_id: nil)

    device.update!(active: false, connected_at: nil)

    render json: { message: "Disconnected successfully" }, status: :ok
  end

  # GET api/credentials/:device_id
  def credentials
    render json: {
      credentials: build_credentials(current_device, assign: false)
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
      secret = ENV['DEVISE_JWT_SECRET_KEY']

      payload = JWT.decode(
        token,
        secret,
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

  # ✅ CRITICAL: Check subscription status in authenticate_device! (not register!)
  def authenticate_device!
    api_key = request.headers['X-Api-Key']

    unless api_key.present?
      render json: {
        error: "API key required",
        message: "Device not registered. Please login again."
      }, status: :unauthorized  # 401
      return
    end

    @current_device = Device.find_by(api_key: api_key)

    unless @current_device
      render json: {
        error: "Invalid API key",
        message: "Device not registered. Please login again."
      }, status: :unauthorized  # 401
      return
    end

    # ✅ STEP 1: Check subscription status (ONLY for /connect, /disconnect, etc.)
    current_subscription = @current_device.subscription

    # Try to auto-link to active subscription if current one is expired/inactive
    unless current_subscription.active?
      active_subscription = @current_device.user.subscriptions.active.first

      if active_subscription
        Rails.logger.info "🔄 Auto-linking device #{@current_device.device_id} from subscription #{current_subscription.id} (#{current_subscription.status}) to active subscription #{active_subscription.id}"
        @current_device.update!(subscription: active_subscription, active: false)

        # Reload to use the new subscription
        @current_device.reload
      else
        # ✅ NO ACTIVE SUBSCRIPTION - Return 403 with renewal info
        render json: {
          error: "No active subscription",
          message: "Your subscription has expired. Please renew to continue using VulcainVPN.",
          subscription_status: current_subscription.status,
          expires_at: current_subscription.expires_at,
          action_required: "renew",
          renewal_url: "https://vulcainvpn.com/pricing"
        }, status: :forbidden  # 403
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

  def build_credentials(device, assign:)
    subscription = device.subscription
    server = subscription.server

    {
      wireguard: build_wireguard_credentials(device, subscription, server, assign: assign),
      hysteria2: build_hysteria2_credentials(device, subscription, server, assign: assign),
      shadowsocks: build_shadowsocks_credentials(device, subscription, server, assign: assign)
    }
  end

  def build_wireguard_credentials(device, subscription, server, assign:)
    client = nil

    ActiveRecord::Base.transaction do
      client = subscription.wireguard_clients.find_by(device_id: device.id)

      if client.nil? && assign
        client = subscription.wireguard_clients
                             .where(device_id: nil)
                             .lock("FOR UPDATE SKIP LOCKED")
                             .first
        client&.update!(device_id: device.id)
      end
    end

    return nil unless client

    {
      server_ip: server.ip_address,
      server_port: server.wireguard_port,
      client_private_key: client.private_key,
      client_public_key: client.public_key,
      client_preshared_key: client.preshared_key,
      client_ip: client.ip_address
    }
  end

  def build_hysteria2_credentials(device, subscription, server, assign:)
    return nil unless server.singbox_active?

    client = nil

    ActiveRecord::Base.transaction do
      client = subscription.hysteria2_clients.find_by(device_id: device.id)

      if client.nil? && assign
        client = subscription.hysteria2_clients
                             .where(device_id: nil)
                             .lock("FOR UPDATE SKIP LOCKED")
                             .first
        client&.update!(device_id: device.id)
      end
    end

    return nil unless client

    {
      server: server.singbox_server_name,
      port: server.singbox_hysteria2_port,
      password: client.password,
      obfs_type: "salamander",
      obfs_password: server.singbox_salamander_password,
      tls_server_name: server.singbox_server_name
    }
  end

  def build_shadowsocks_credentials(device, subscription, server, assign:)
    return nil unless server.singbox_active?

    client = nil

    ActiveRecord::Base.transaction do
      client = subscription.shadowsocks_clients.find_by(device_id: device.id)

      if client.nil? && assign
        client = subscription.shadowsocks_clients
                             .where(device_id: nil)
                             .lock("FOR UPDATE SKIP LOCKED")
                             .first
        client&.update!(device_id: device.id)
      end
    end

    return nil unless client

    {
      server: server.ip_address,
      port: server.singbox_ss_port,
      method: "2022-blake3-aes-256-gcm",
      password: "#{server.singbox_ss_master_password}:#{client.password}"
    }
  end
end
