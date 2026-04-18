# app/jobs/clash_api_monitor_job.rb
require 'net/http'
require 'json'

class ClashApiMonitorJob < ApplicationJob
  queue_as :default

  CLASH_API_PORT = 9090
  DEACTIVATION_GRACE_PERIOD = 5.minutes

  def perform
    devices_with_real_connections = Set.new

    Server.active.healthy.where(singbox_active: true).find_each do |server|
      active_device_ids = monitor_server(server)
      devices_with_real_connections.merge(active_device_ids)
    end

    # Mark devices with real connections as active
    if devices_with_real_connections.any?
      Device.where(id: devices_with_real_connections).update_all(
        active: true,
        last_seen_at: Time.current
      )
    end

    # Deactivate devices that have been inactive for > grace period
    currently_active_device_ids = Device.where(active: true).pluck(:id)
    potentially_inactive_device_ids = currently_active_device_ids - devices_with_real_connections.to_a

    if potentially_inactive_device_ids.any?
      devices_to_deactivate = Device
        .where(id: potentially_inactive_device_ids)
        .where('last_seen_at < ?', DEACTIVATION_GRACE_PERIOD.ago)
        .pluck(:id)

      if devices_to_deactivate.any?
        # ⭐ NEW: Release configs back to pool
        release_configs_for_devices(devices_to_deactivate)

        Device.where(id: devices_to_deactivate).update_all(
          active: false,
          last_seen_at: Time.current
        )

        Rails.logger.info "🔴 Deactivated #{devices_to_deactivate.size} devices (inactive > #{DEACTIVATION_GRACE_PERIOD.inspect})"
      end

      devices_in_grace = potentially_inactive_device_ids - devices_to_deactivate
      if devices_in_grace.any?
        Rails.logger.info "⏳ #{devices_in_grace.size} devices in grace period"
      end
    end
  end

  private

  def monitor_server(server)
    connections = get_active_connections(server)
    Rails.logger.info "🔌 Found #{connections.size} active connections on #{server.name}"

    active_device_ids = Set.new
    matched_connections = Set.new

    connections.each do |conn|
      source_ip = conn.dig("metadata", "sourceIP")
      next unless source_ip

      # ⭐ NEW: In pooling, username IS the IP address
      # Find the config set by IP
      config_set = VpnConfigSet.find_by(server: server, ip_address: source_ip, status: 'in_use')

      unless config_set
        Rails.logger.warn "⚠️ No config set for IP: #{source_ip}"
        next
      end

      device = config_set.device
      unless device
        Rails.logger.warn "⚠️ Config set #{source_ip} has no device"
        next
      end

      # Check subscription status
      unless device.subscription&.active?
        kill_connection(server, conn["id"])
        Rails.logger.warn "❌ Killed unauthorized: #{source_ip}"
        next
      end

      Rails.logger.info "✅ Active: #{source_ip} → Device #{device.id}"
      active_device_ids << device.id
    end

    Rails.logger.info "✅ #{active_device_ids.size} active devices on #{server.name}"
    active_device_ids.to_a
  end

  def get_active_connections(server)
    uri = URI("http://#{server.ip_address}:#{CLASH_API_PORT}/connections")

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{server.clash_api_secret}"

    response = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 10) do |http|
      http.request(request)
    end

    return [] unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    data["connections"] || []
  rescue => e
    Rails.logger.error "Failed to get connections from #{server.name}: #{e.message}"
    []
  end

  def kill_connection(server, connection_id)
    uri = URI("http://#{server.ip_address}:#{CLASH_API_PORT}/connections/#{connection_id}")

    request = Net::HTTP::Delete.new(uri)
    request['Authorization'] = "Bearer #{server.clash_api_secret}"

    Net::HTTP.start(uri.hostname, uri.port, read_timeout: 5) do |http|
      http.request(request)
    end
  rescue => e
    Rails.logger.error "Failed to kill connection: #{e.message}"
  end

  # ⭐ NEW: Release configs back to pool instead of freeing individual clients
  def release_configs_for_devices(device_ids)
    return if device_ids.empty?

    VpnConfigSet.where(device_id: device_ids, status: 'in_use').find_each do |config_set|
      config_set.release!
      Rails.logger.info "Released config #{config_set.ip_address} back to pool"
    end

    # Close active connections
    VpnConnection.where(device_id: device_ids, disconnected_at: nil).update_all(disconnected_at: Time.current)

    Rails.logger.info "🔓 Released configs for #{device_ids.size} devices"
  end
end
