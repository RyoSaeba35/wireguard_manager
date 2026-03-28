# app/jobs/clash_api_monitor_job.rb
class ClashApiMonitorJob < ApplicationJob
  queue_as :default

  CLASH_API_PORT = 9090

  def perform
    devices_with_real_connections = Set.new

    Server.where(active: true, singbox_active: true).find_each do |server|
      active_device_ids = monitor_server(server)
      devices_with_real_connections.merge(active_device_ids)
    end

    # Mark devices WITH real connections as active
    if devices_with_real_connections.any?
      Device.where(id: devices_with_real_connections).update_all(
        active: true,
        last_seen_at: Time.current
      )
    end

    # Mark devices WITHOUT real connections as inactive
    currently_active_device_ids = Device.where(active: true).pluck(:id)
    devices_to_deactivate = currently_active_device_ids - devices_with_real_connections.to_a

    if devices_to_deactivate.any?
      # ⭐ Free clients before deactivating
      free_clients_for_devices(devices_to_deactivate)

      Device.where(id: devices_to_deactivate).update_all(
        active: false,
        last_seen_at: Time.current
      )
      Rails.logger.info "🔴 Deactivated #{devices_to_deactivate.size} devices with no real connections"
    end
  end

  private

  def monitor_server(server)
    response = HTTParty.get(
      "http://#{server.ip_address}:#{CLASH_API_PORT}/connections",
      headers: { "Authorization" => "Bearer #{server.clash_api_secret}" },
      timeout: 5
    )

    return [] unless response.success?

    connections = response.parsed_response["connections"] || []
    username_connections = {}
    active_device_ids = Set.new

    connections.each do |connection|
      username = connection.dig("metadata", "inboundUser")
      next unless username.present?

      client = find_client(username)
      next unless client

      device = client.device

      unless device&.subscription&.active?
        kill_connection(server, connection["id"])
        Rails.logger.warn "❌ Killed unauthorized: #{username}"
        next
      end

      username_connections[username] ||= []
      username_connections[username] << connection["id"]
      active_device_ids << device.id
    end

    enforce_single_connection(server, username_connections)
    active_device_ids.to_a

  rescue => e
    Rails.logger.error "ClashApiMonitorJob failed for #{server.name}: #{e.message}"
    []
  end

  def find_client(username)
    Hysteria2Client.find_by(name: username) ||
      ShadowsocksClient.find_by(name: username)
      # Add WireguardClient if it uses Clash API
  end

  def enforce_single_connection(server, username_connections)
    username_connections.each do |username, connection_ids|
      next if connection_ids.size <= 1

      connection_ids[1..].each do |connection_id|
        kill_connection(server, connection_id)
        Rails.logger.warn "⚠️ Killed duplicate: #{username}"
      end
    end
  end

  def kill_connection(server, connection_id)
    HTTParty.delete(
      "http://#{server.ip_address}:#{CLASH_API_PORT}/connections/#{connection_id}",
      headers: { "Authorization" => "Bearer #{server.clash_api_secret}" },
      timeout: 5
    )
  rescue => e
    Rails.logger.error "Failed to kill connection: #{e.message}"
  end

  # ⭐ NEW: Free protocol clients when deactivating devices
  def free_clients_for_devices(device_ids)
    return if device_ids.empty?

    Hysteria2Client.where(device_id: device_ids).update_all(device_id: nil)
    ShadowsocksClient.where(device_id: device_ids).update_all(device_id: nil)
    WireguardClient.where(device_id: device_ids).update_all(device_id: nil)

    Rails.logger.info "🔓 Freed clients for #{device_ids.size} inactive devices"
  end
end
