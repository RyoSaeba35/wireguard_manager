# app/controllers/api/subscriptions_controller.rb
class Api::SubscriptionsController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!, raise: false

  before_action :authenticate_api_user!, only: [:show]
  before_action :authenticate_device!, only: [:show_by_device]

  # GET api/subscription (JWT auth)
  def show
    # ✅ FIXED: Remove .active filter, get any subscription
    subscription = @current_api_user.subscriptions.order(created_at: :desc).first

    unless subscription
      render json: { error: "No subscription found" }, status: :not_found
      return
    end

    render json: {
      subscription: subscription_json(subscription)
    }, status: :ok
  end

  # GET api/subscription/device/:device_id (API Key auth)
  def show_by_device
    # ✅ Get subscription regardless of status
    subscription = @current_device.user.subscriptions.order(created_at: :desc).first

    unless subscription
      render json: { error: "No subscription found" }, status: :not_found
      return
    end

    # ✅ Return subscription with actual status (active/expired/canceled)
    render json: {
      subscription: subscription_json(subscription)
    }, status: :ok
  end

  private

  def subscription_json(subscription)
    # Get current connection info (only if subscription is active)
    active_connection = subscription.status == 'active' ?
                        subscription.vpn_connections.active.includes(:server).first :
                        nil

    {
      name: subscription.name,
      status: subscription.status,  # ✅ This will be "expired" when expired!
      expires_at: subscription.expires_at,
      plan: {
        name: subscription.plan.name,
        interval: subscription.plan.interval
      },
      server: active_connection ? {
        name: active_connection.server.name,
        location: active_connection.server.location || active_connection.server.city,
        country: active_connection.server.country_code,
        flag: active_connection.server.flag
      } : nil,
      devices: {
        total: subscription.devices.count,
        active: subscription.devices.where(active: true).count,
        max: subscription.max_devices
      },
      active_connections: subscription.vpn_connections.active.count
    }
  end

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
    device_id = params[:device_id]
    api_key = request.headers['X-Api-Key']

    unless device_id.present? && api_key.present?
      render json: { error: 'Device ID and API Key required' }, status: :unauthorized
      return
    end

    @current_device = Device.find_by(device_id: device_id, api_key: api_key)

    unless @current_device
      render json: { error: 'Invalid device credentials' }, status: :unauthorized
      return
    end
  end
end
