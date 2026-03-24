# app/controllers/api/subscriptions_controller.rb
class Api::SubscriptionsController < ApplicationController
  protect_from_forgery with: :null_session
  before_action :authenticate_user!  # ⭐ Use JWT instead

  def show
    subscription = current_user.subscriptions.last

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
end
