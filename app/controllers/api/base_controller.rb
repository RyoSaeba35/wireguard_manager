# app/controllers/api/base_controller.rb
class Api::BaseController < ApplicationController
  skip_before_action :authenticate_user!
  protect_from_forgery with: :null_session
  before_action :authenticate_device!

  private

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

  def current_user
    @current_device.user
  end
end
