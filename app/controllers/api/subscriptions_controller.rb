# app/controllers/api/subscriptions_controller.rb
class Api::SubscriptionsController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!, raise: false

  # ✅ JWT auth pour la méthode show
  before_action :authenticate_api_user!, only: [:show]

  # ✅ NEW: API Key auth pour la méthode show_by_device
  before_action :authenticate_device!, only: [:show_by_device]

  # Existing method - Pour Flutter UI (JWT)
  def show
    subscription = @current_api_user.subscriptions.last

    unless subscription
      render json: { error: "No subscription found" }, status: :not_found
      return
    end

    render json: {
      subscription: {
        name: subscription.name,
        status: subscription.status,
        expires_at: subscription.expires_at,
        plan: {
          name: subscription.plan.name,
          interval: subscription.plan.interval
        },
        server: {
          name: subscription.server.name,
          location: subscription.server.singbox_server_name
        },
        devices: {
          total: subscription.devices.count,
          active: subscription.devices.where(active: true).count,
          max: Api::DevicesController::MAX_DEVICES
        }
      }
    }, status: :ok
  end

  # ✅ NEW: Pour Android heartbeat (API Key)
  def show_by_device
    # @current_device est défini par authenticate_device!
    user = @current_device.user
    subscription = user.subscriptions.last

    unless subscription
      render json: { error: "No subscription found" }, status: :not_found
      return
    end

    # ✅ Retourne exactement le même format que show()
    render json: {
      subscription: {
        name: subscription.name,
        status: subscription.status,
        expires_at: subscription.expires_at,
        plan: {
          name: subscription.plan.name,
          interval: subscription.plan.interval
        },
        server: {
          name: subscription.server.name,
          location: subscription.server.singbox_server_name
        },
        devices: {
          total: subscription.devices.count,
          active: subscription.devices.where(active: true).count,
          max: Api::DevicesController::MAX_DEVICES
        }
      }
    }, status: :ok
  end

  private

  # Existing - JWT authentication
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

      # Check if token was revoked
      if JwtDenylist.exists?(jti: payload['jti'])
        render json: { error: "Token has been revoked" }, status: :unauthorized
        return
      end

      @current_api_user = User.find(payload['sub'])

    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render json: { error: "Invalid or expired token" }, status: :unauthorized
    end
  end

  # ✅ NEW: API Key authentication (pour heartbeat)
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
