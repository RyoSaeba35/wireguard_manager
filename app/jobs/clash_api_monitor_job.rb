# app/jobs/clash_api_monitor_job.rb
require 'net/http'
require 'json'

class ClashApiMonitorJob < ApplicationJob
  queue_as :default

  CLASH_API_PORT = 9090
  LOG_FILE_PATH = "/var/log/sing-box/connections.log"
  LINES_TO_READ = 5000  # Read last 5000 lines (covers ~5-10 minutes of activity)

  def perform
    devices_with_real_connections = Set.new

    Server.where(active: true, singbox_active: true).find_each do |server|
      active_device_ids = monitor_server(server)
      devices_with_real_connections.merge(active_device_ids)
    end

    if devices_with_real_connections.any?
      Device.where(id: devices_with_real_connections).update_all(
        active: true,
        last_seen_at: Time.current
      )
    end

    currently_active_device_ids = Device.where(active: true).pluck(:id)
    devices_to_deactivate = currently_active_device_ids - devices_with_real_connections.to_a

    if devices_to_deactivate.any?
      free_clients_for_devices(devices_to_deactivate)
      Device.where(id: devices_to_deactivate).update_all(
        active: false,
        last_seen_at: Time.current
      )
      Rails.logger.info "🔴 Deactivated #{devices_to_deactivate.size} devices"
    end
  end

  private

  def monitor_server(server)
    # Read recent log entries from file (FAST - no waiting!)
    username_to_port = read_log_file(server)

    Rails.logger.info "📊 Found #{username_to_port.size} username mappings from log file"

    # Get active connections
    connections = get_active_connections(server)

    Rails.logger.info "🔌 Found #{connections.size} active connections"

    # Match connections to usernames
    active_device_ids = Set.new

    connections.each do |conn|
      source_ip = conn.dig("metadata", "sourceIP")
      source_port = conn.dig("metadata", "sourcePort")

      username = username_to_port["#{source_ip}:#{source_port}"]

      if username
        Rails.logger.info "✅ Matched: #{source_ip}:#{source_port} → #{username}"

        client = find_client(username)
        next unless client&.device

        device = client.device

        unless device.subscription&.active?
          kill_connection(server, conn["id"])
          Rails.logger.warn "❌ Killed unauthorized: #{username}"
          next
        end

        active_device_ids << device.id
      else
        Rails.logger.warn "⚠️ No username for: #{source_ip}:#{source_port}"
      end
    end

    Rails.logger.info "✅ #{active_device_ids.size} active devices"
    active_device_ids.to_a

  rescue => e
    Rails.logger.error "Monitor failed: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")
    []
  end

  def read_log_file(server)
    mapping = {}

    # Use SSH to read last N lines from remote log file
    # Or if Rails is on same server: just read directly
    log_content = ssh_read_log_tail(server)

    log_content.each_line do |line|
      # Parse log format (adjust based on your actual format)
      # Example: [2026-03-28 14:30:45] [info] inbound/hysteria2[hysteria2-in]: inbound connection from 176.143.53.46:54657
      # Example: [2026-03-28 14:30:45] [info] inbound/hysteria2[hysteria2-in]: [NAUIZ_1] inbound connection to www.google.com:443

      ip_port_match = line.match(/from\s+([\d\.]+):(\d+)/)
      username_match = line.match(/\[([A-Z0-9_]+)\]/)

      if ip_port_match && username_match
        ip = ip_port_match[1]
        port = ip_port_match[2]
        username = username_match[1]

        mapping["#{ip}:#{port}"] = username
      end
    end

    mapping
  rescue => e
    Rails.logger.error "Failed to read log file: #{e.message}"
    {}
  end

  def ssh_read_log_tail(server)
    # Option 1: If Rails runs ON the sing-box server (same machine)
    if server.ip_address == "127.0.0.1" || server.ip_address == "localhost"
      `tail -n #{LINES_TO_READ} #{LOG_FILE_PATH} 2>/dev/null` || ""
    else
      # Option 2: If Rails is remote, use SSH
      require 'net/ssh'

      log_content = ""
      Net::SSH.start(server.ip_address, 'root', keys: ['/path/to/ssh/key']) do |ssh|
        log_content = ssh.exec!("tail -n #{LINES_TO_READ} #{LOG_FILE_PATH}")
      end
      log_content
    end
  rescue => e
    Rails.logger.error "SSH read failed: #{e.message}"
    ""
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
    Rails.logger.error "Failed to get connections: #{e.message}"
    []
  end

  def find_client(username)
    Hysteria2Client.find_by(name: username) ||
      ShadowsocksClient.find_by(name: username) ||
      WireguardClient.find_by(name: username)
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

  def free_clients_for_devices(device_ids)
    return if device_ids.empty?

    Hystparty2Client.where(device_id: device_ids).update_all(device_id: nil)
    ShadowsocksClient.where(device_id: device_ids).update_all(device_id: nil)
    WireguardClient.where(device_id: device_ids).update_all(device_id: nil)

    Rails.logger.info "🔓 Freed clients for #{device_ids.size} devices"
  end
end
