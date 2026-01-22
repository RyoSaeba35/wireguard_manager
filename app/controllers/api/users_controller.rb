module Api
  class UsersController < Api::BaseController
    # GET /api/status
    def status
      subscription = @current_user.subscriptions.find_by(status: 'active')
      active_devices = @current_user.devices.where(active: true)

      active_devices_count = active_devices.count
      max_devices = subscription ? 3 : 0
      remaining_slots = [max_devices - active_devices_count, 0].max

      render json: {
        success: true,
        active_subscription: subscription.present?,
        expires_at: subscription&.expires_at,
        active_devices_count: active_devices_count,
        max_devices: max_devices,
        remaining_slots: remaining_slots,
        devices: active_devices.map { |d| device_json(d) }
      }
    end

    private

    def device_json(device)
      {
        id: device.id,
        device_id: device.device_id,
        platform: device.platform,
        name: device.name,
        last_seen_at: device.last_seen_at,
        active: device.active,
        has_api_key: device.api_key.present?
      }
    end
  end
end
