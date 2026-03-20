# app/controllers/api/subscriptions_controller.rb
class Api::SubscriptionsController < Api::BaseController

  # GET api/subscription
  def show
    subscription = current_subscription

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
