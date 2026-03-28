# app/jobs/clash_api_monitor_job.rb
class ClashApiMonitorJob < ApplicationJob
  queue_as :default

  CLASH_API_PORT = 9090
  ACTIVITY_THRESHOLD = 2.minutes  # User must have log activity within 2 minutes

  def perform
    devices_with_real_activity = Set.new

    Server.where(active: true, singbox_active: true).find_each do |server|
      active_device_ids = monitor_server(server)
      devices_with_real_activity.merge(active_device_ids)
    end

    # Mark devices WITH real activity as active
    if devices_with_real_activity.any?
      Device.where(id: devices_with_real_activity).update_all(
        active: true,
        last_seen_at: Time.current
      )
    end

    # Mark devices WITHOUT real activity as inactive
    currently_active_device_ids = Device.where(active: true).pluck(:id)
    devices_to_deactivate = currently_active_device_ids - devices_with_real_activity.to_a

    if devices_to_deactivate.any?
      free_clients_for_devices(devices_to_deactivate)

      Device.where(id: devices_to_deactivate).update_all(
        active: false,
        last_seen_at: Time.current
      )
      Rails.logger.info "🔴 Deactivated #{devices_to_deactivate.size} devices with no real activity"
    end
  end

  private

  def monitor_server(server)
    # Get recent logs
    response = HTTParty.get(
      "http://#{server.ip_address}:#{CLASH_API_PORT}/logs",
      headers: { "Authorization" => "Bearer #{server.clash_api_secret}" },
      timeout: 5
    )

    return [] unless response.success?

    # Parse the streaming log response (each line is a JSON object)
    log_lines = response.body.split("\n").map do |line|
      JSON.parse(line) rescue nil
    end.compact

    # Extract usernames from logs
    active_usernames = extract_active_usernames(log_lines)

    Rails.logger.info "📊 Active users on #{server.name}: #{active_usernames.to_a.join(', ')}"

    # Find devices for these usernames
    active_device_ids = Set.new

    active_usernames.each do |username|
      client = find_client(username)
      next unless client

      device = client.device
      next unless device

      # Check authorization
      unless device.subscription&.active?
        Rails.logger.warn "❌ Unauthorized user still active: #{username}"
        # Note: We can't kill specific connections via logs, but marking inactive will help
        next
      end

      active_device_ids << device.id
    end

    active_device_ids.to_a

  rescue => e
    Rails.logger.error "ClashApiMonitorJob failed for #{server.name}: #{e.message}"
    []
  end

  def extract_active_usernames(log_lines)
    usernames = Set.new

    log_lines.each do |log|
      payload = log["payload"]
      next unless payload

      # Match pattern: [USERNAME] in the log message
      # Example: "[NAUIZ_2] inbound connection to push.prod.netflix.com:443"
      match = payload.match(/\[([A-Z0-9_]+)\]/)
      if match
        username = match[1]
        usernames << username
      end
    end

    usernames
  end

  def find_client(username)
    Hysteria2Client.find_by(name: username) ||
      ShadowsocksClient.find_by(name: username) ||
      WireguardClient.find_by(name: username)
  end

  def free_clients_for_devices(device_ids)
    return if device_ids.empty?

    Hysteria2Client.where(device_id: device_ids).update_all(device_id: nil)
    ShadowsocksClient.where(device_id: device_ids).update_all(device_id: nil)
    WireguardClient.where(device_id: device_ids).update_all(device_id: nil)

    Rails.logger.info "🔓 Freed clients for #{device_ids.size} inactive devices"
  end
end
