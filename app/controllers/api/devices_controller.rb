# app/controllers/api/devices_controller.rb
class Api::DevicesController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!, raise: false
  before_action :authenticate_api_user!, only: [:register]
  before_action :authenticate_device!, only: [:connect, :disconnect, :heartbeat, :credentials]

  MAX_DEVICES = 3

  # POST api/devices/register
  # No limit on registered devices — only active connections are limited
  def register
    subscription = @current_api_user.subscriptions.active.first

    unless subscription
      render json: { error: "No active subscription found" }, status: :forbidden
      return
    end

    # Find or create — unlimited registered devices per subscription
    device = subscription.devices.find_or_initialize_by(
      device_id: params[:device_id]
    )

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
  # Checks 3-active-session limit, assigns clients, marks device active
# app/controllers/api/devices_controller.rb

  def connect
    subscription = current_subscription

    active_count = subscription.devices
                              .where(active: true)
                              .where.not(id: current_device.id)
                              .count

    if active_count >= MAX_DEVICES
      render json: {
        error: "Maximum #{MAX_DEVICES} simultaneous connections reached",
        active_devices: active_count
      }, status: :too_many_requests
      return
    end

    # Build credentials first to determine protocol
    credentials = build_credentials(current_device, assign: true)

    # Determine which protocol was assigned
    protocol_type = if credentials[:hysteria2]
      "hysteria2"
    elsif credentials[:shadowsocks]
      "shadowsocks"
    elsif credentials[:wireguard]
      "wireguard"
    else
      "unknown"
    end

    current_device.update!(
      active: true,
      connected_at: Time.current,
      last_seen_at: Time.current,
      last_connection_ip: request.remote_ip,      # ⭐ NEW
      last_protocol_type: protocol_type            # ⭐ NEW
    )

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

  # # POST api/heartbeat/:device_id
  # def heartbeat
  #   current_device.update!(
  #     active: true,
  #     last_heartbeat_at: Time.current,
  #     last_seen_at: Time.current
  #   )

  #   render json: { message: "OK" }, status: :ok
  # end

  # GET api/credentials/:device_id
  # Returns already-assigned credentials only — never assigns
  # Use /connect to get credentials assigned for the first time
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

  def authenticate_device!
    api_key = request.headers['X-Api-Key']

    unless api_key.present?
      render json: { error: "API key required" }, status: :unauthorized
      return
    end

    @current_device = Device.find_by(api_key: api_key)

    unless @current_device
      render json: { error: "Invalid API key" }, status: :unauthorized
      return
    end

    unless @current_device.subscription.active?
      render json: { error: "Subscription is not active" }, status: :forbidden
      return
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
