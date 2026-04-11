# app/controllers/api/subscriptions_controller.rb
class Api::SubscriptionsController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!, raise: false  # ← Skip Devise web auth
  before_action :authenticate_api_user!  # ← Use JWT auth instead

  def show
    subscription = @current_api_user.subscriptions.last  # ← Use @current_api_user

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

  private

  # Copy this from Api::DevicesController
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

      # ✅ ADD THIS: Check if token was revoked
      if JwtDenylist.exists?(jti: payload['jti'])
        render json: { error: "Token has been revoked" }, status: :unauthorized
        return
      end

      @current_api_user = User.find(payload['sub'])

    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render json: { error: "Invalid or expired token" }, status: :unauthorized
    end
  end
end
