# app/controllers/api/users_controller.rb
class Api::UsersController < Api::BaseController
  # GET api/status
  def status
    subscription = current_subscription

    render json: {
      user: {
        email: current_user.email
      },
      subscription: {
        active: subscription.active?,
        expires_at: subscription.expires_at,
        days_remaining: [((subscription.expires_at - Time.current) / 1.day).floor, 0].max
      },
      device: {
        id: current_device.device_id,
        name: current_device.name,
        platform: current_device.platform,
        active: current_device.active,
        last_seen_at: current_device.last_seen_at
      }
    }, status: :ok
  end
end
