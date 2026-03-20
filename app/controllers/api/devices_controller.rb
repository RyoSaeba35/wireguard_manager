# app/controllers/api/devices_controller.rb
class Api::DevicesController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!
  before_action :authenticate_api_user!, only: [:register]
  before_action :authenticate_device!, only: [:connect, :disconnect, :heartbeat, :credentials]

  MAX_DEVICES = 3

  # POST api/devices/register
  def register
    subscription = @current_api_user.subscriptions.active.first

    unless subscription
      render json: { error: "No active subscription found" }, status: :forbidden
      return
    end

    # Find existing device first
    device = subscription.devices.find_by(device_id: params[:device_id])

    # Only check limit for new devices
    unless device
      if subscription.devices.count >= MAX_DEVICES
        render json: { error: "Maximum of #{MAX_DEVICES} devices allowed per subscription" }, status: :forbidden
        return
      end
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

    active_count = subscription.devices
                               .where(active: true)
                               .where.not(id: current_device.id)
                               .count

    if active_count >= MAX_DEVICES
      render json: { error: "Maximum #{MAX_DEVICES} simultaneous connections reached" }, status: :too_many_requests
      return
    end

    current_device.update!(
      active: true,
      connected_at: Time.current,
      last_heartbeat_at: Time.current,
      last_seen_at: Time.current
    )

    render json: {
      message: "Connected successfully",
      credentials: build_credentials(current_device)
    }, status: :ok
  end

  # POST api/disconnect/:device_id
  def disconnect
    current_device.update!(
      active: false,
      connected_at: nil
    )

    render json: { message: "Disconnected successfully" }, status: :ok
  end

  # POST api/heartbeat/:device_id
  def heartbeat
    current_device.update!(
      last_heartbeat_at: Time.current,
      last_seen_at: Time.current
    )

    render json: { message: "OK" }, status: :ok
  end

  # GET api/credentials/:device_id
  def credentials
    render json: {
      credentials: build_credentials(current_device)
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
        Rails.application.credentials.devise_jwt_secret_key,
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
    end
  end

  def current_device
    @current_device
  end

  def current_subscription
    @current_device.subscription
  end

  def build_credentials(device)
    subscription = device.subscription
    server = subscription.server

    {
      wireguard: build_wireguard_credentials(device, subscription, server),
      hysteria2: build_hysteria2_credentials(device, subscription, server),
      shadowsocks: build_shadowsocks_credentials(device, subscription, server)
    }
  end

  def build_wireguard_credentials(device, subscription, server)
    client = subscription.wireguard_clients.find_by(device_id: device.id) ||
             subscription.wireguard_clients.where(device_id: nil).lock.first

    return nil unless client

    client.update!(device_id: device.id) if client.device_id.nil?

    {
      server_ip: server.ip_address,
      server_port: server.wireguard_port,
      server_public_key: server.wireguard_public_key,
      client_private_key: client.private_key,
      client_public_key: client.public_key,
      client_ip: client.ip_address
    }
  end

  def build_hysteria2_credentials(device, subscription, server)
    return nil unless server.singbox_active?

    client = subscription.hysteria2_clients.find_by(device_id: device.id) ||
             subscription.hysteria2_clients.where(device_id: nil).lock.first

    return nil unless client

    client.update!(device_id: device.id) if client.device_id.nil?

    {
      server: server.singbox_server_name,
      port: server.singbox_hysteria2_port,
      password: client.password,
      obfs_type: "salamander",
      obfs_password: server.singbox_salamander_password,
      tls_server_name: server.singbox_server_name
    }
  end

  def build_shadowsocks_credentials(device, subscription, server)
    return nil unless server.singbox_active?

    client = subscription.shadowsocks_clients.find_by(device_id: device.id) ||
             subscription.shadowsocks_clients.where(device_id: nil).lock.first

    return nil unless client

    client.update!(device_id: device.id) if client.device_id.nil?

    {
      server: server.ip_address,
      port: server.singbox_ss_port,
      method: "2022-blake3-aes-256-gcm",
      password: "#{server.singbox_ss_master_password}:#{client.password}"
    }
  end
end
