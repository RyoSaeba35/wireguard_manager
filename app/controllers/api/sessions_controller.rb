module Api
  class SessionsController < Api::BaseController
    skip_before_action :authenticate_request!, only: [:create] # login doesn’t need JWT

    # POST /api/login
    def create
      user = User.find_for_database_authentication(email: params[:email])

      if user&.valid_password?(params[:password])
        token = Warden::JWTAuth::UserEncoder
          .new
          .call(user, :user, nil)
          .first

        subscription = user.subscriptions.find_by(status: 'active')
        active_devices_count = user.devices.where(active: true).count
        max_devices = subscription ? 3 : 0
        remaining_slots = [max_devices - active_devices_count, 0].max

        device = nil
        api_key = nil

        if params[:device_id].present? && subscription.present?
          device = user.devices.find_or_create_by(
            device_id: params[:device_id],
            subscription: subscription
          ) do |d|
            d.platform = params[:platform] || "mobile"
            d.name = params[:name] || "Flutter app"
            d.active = true
          end

          if device.api_key.blank?
            device.update!(api_key: SecureRandom.hex(32))
          end

          api_key = device.api_key
        end

        render json: {
          success: true,
          jwt: token,
          api_key: api_key,
          user: {
            id: user.id,
            email: user.email,
            admin: user.admin,
            active_subscription: subscription.present?,
            subscription_expires_at: subscription&.expires_at,
            active_devices_count: active_devices_count,
            max_devices: max_devices,
            remaining_slots: remaining_slots
          }
        }
      else
        render json: {
          success: false,
          error: "Invalid email or password"
        }, status: :unauthorized
      end
    end

    # DELETE /api/logout
    def destroy
      render json: { success: true }
    end
  end
end
