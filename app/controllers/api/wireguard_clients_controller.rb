module Api
  class WireguardClientsController < Api::BaseController
    # GET /api/config/:device_id
    def config
      subscription = @current_user.subscriptions.find_by(status: 'active')
      unless subscription
        return render json: {
          success: false,
          error: "No active subscription"
        }, status: :forbidden
      end

      # 🔐 Never allow silent device creation without subscription
      device = @current_user.devices.find_or_initialize_by(
        device_id: params[:device_id],
        subscription: subscription
      )

      if device.new_record?
        device.assign_attributes(
          platform: params[:platform],
          name: params[:name],
          active: false
        )
        device.save!
      end

      # 🔐 Ensure device has an API key
      if device.api_key.blank?
        device.update!(api_key: SecureRandom.hex(32))
      end

      active_devices = subscription.devices.where(active: true)
      active_devices_count = active_devices.count
      max_devices = 3
      remaining_slots = [max_devices - active_devices_count, 0].max

      # 🔐 HARD limit enforcement
      if !device.active && active_devices_count >= max_devices
        return render json: {
          success: false,
          error: "Maximum active devices reached",
          active_devices_count: active_devices_count,
          max_devices: max_devices,
          remaining_slots: remaining_slots,
          active_devices: active_devices.map { |d| device_json(d) }
        }, status: :forbidden
      end

      wg_client = nil

      # 🔐 Prevent race conditions
      WireguardClient.transaction do
        wg_client = subscription
          .wireguard_clients
          .lock
          .where(device: nil, status: 'active')
          .first

        if wg_client
          wg_client.update!(device: device)
          device.update!(
            active: true,
            last_seen_at: Time.current
          )
        end
      end

      unless wg_client
        return render json: {
          success: false,
          error: "No WireGuard clients available",
          active_devices_count: active_devices_count,
          max_devices: max_devices,
          remaining_slots: remaining_slots,
          active_devices: active_devices.map { |d| device_json(d) }
        }, status: :unprocessable_entity
      end

      render json: {
        success: true,
        config: generate_sing_box_config(wg_client),
        active_devices_count: active_devices_count + 1,
        max_devices: max_devices,
        remaining_slots: remaining_slots - 1,
        active_devices: (
          active_devices.map { |d| device_json(d) } +
          [device_json(device)]
        )
      }
    end

    # POST /api/revoke/:device_id
    def revoke
      device = @current_user.devices.find_by(device_id: params[:device_id])
      unless device
        return render json: {
          success: false,
          error: "Device not found"
        }, status: :not_found
      end

      wg_client = device.wireguard_client

      WireguardClient.transaction do
        wg_client&.update!(device: nil)
        device.update!(
          active: false,
          api_key: nil
        )
      end

      subscription = device.subscription
      active_devices = subscription.devices.where(active: true)
      active_devices_count = active_devices.count
      max_devices = 3
      remaining_slots = [max_devices - active_devices_count, 0].max

      render json: {
        success: true,
        active_devices_count: active_devices_count,
        max_devices: max_devices,
        remaining_slots: remaining_slots,
        active_devices: active_devices.map { |d| device_json(d) }
      }
    end

    private

    # 🔐 NEVER log or expose private keys in logs
    def generate_sing_box_config(wg_client)
      {
        name: wg_client.name,
        public_key: wg_client.public_key,
        private_key: wg_client.private_key,
        ip_address: wg_client.ip_address,
        server_ip: wg_client.subscription.server.wireguard_server_ip
      }
    end

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
