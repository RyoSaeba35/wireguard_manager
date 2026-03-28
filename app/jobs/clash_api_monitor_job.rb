# app/jobs/clash_api_monitor_job.rb
require 'net/http'
require 'json'

class ClashApiMonitorJob < ApplicationJob
  queue_as :default

  CLASH_API_PORT = 9090

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
    # Step 1: Read streaming logs for 2 seconds to get recent activity
    username_to_port = read_streaming_logs(server)

    Rails.logger.info "📊 Found #{username_to_port.size} username mappings on #{server.name}"

    # Step 2: Get active connections
    connections = get_active_connections(server)

    Rails.logger.info "🔌 Found #{connections.size} active connections on #{server.name}"

    # Step 3: Match connections to usernames
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
        Rails.logger.warn "⚠️ No username for connection: #{source_ip}:#{source_port}"
      end
    end

    Rails.logger.info "✅ #{active_device_ids.size} active devices on #{server.name}"
    active_device_ids.to_a

  rescue => e
    Rails.logger.error "Monitor failed for #{server.name}: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")
    []
  end

  def read_streaming_logs(server)
    mapping = {}

    uri = URI("http://#{server.ip_address}:#{CLASH_API_PORT}/logs")

    begin
      Net::HTTP.start(uri.host, uri.port, read_timeout: 5, open_timeout: 5) do |http|  # ⭐ Changed from 2 to 5
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{server.clash_api_secret}"

        http.request(request) do |response|
          buffer = ""
          lines_processed = 0

          # Read chunks for up to 5 seconds
          begin
            response.read_body do |chunk|
              buffer << chunk

              # Process complete lines
              while buffer.include?("\n")
                line, buffer = buffer.split("\n", 2)
                lines_processed += 1

                begin
                  log = JSON.parse(line)
                  payload = log["payload"]
                  next unless payload

                  # Extract IP:port and username
                  ip_port_match = payload.match(/from\s+([\d\.]+):(\d+)/)
                  username_match = payload.match(/\[([A-Z0-9_]+)\]/)

                  if ip_port_match && username_match
                    ip = ip_port_match[1]
                    port = ip_port_match[2]
                    username = username_match[1]

                    mapping["#{ip}:#{port}"] = username
                  end
                rescue JSON::ParserError
                  next
                end
              end
            end
          rescue Net::ReadTimeout
            # This is expected - we read for 5 seconds then timeout
            Rails.logger.info "Logs read complete (timeout after 5s) - processed #{lines_processed} lines, collected #{mapping.size} mappings"
          end
        end
      end
    rescue Net::OpenTimeout, Errno::ECONNREFUSED => e
      Rails.logger.error "Cannot connect to logs endpoint: #{e.message}"
    rescue => e
      unless e.is_a?(Net::ReadTimeout)
        Rails.logger.error "Unexpected logs read error: #{e.class} - #{e.message}"
      end
    end

    mapping
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

    Hysteria2Client.where(device_id: device_ids).update_all(device_id: nil)
    ShadowsocksClient.where(device_id: device_ids).update_all(device_id: nil)
    WireguardClient.where(device_id: device_ids).update_all(device_id: nil)

    Rails.logger.info "🔓 Freed clients for #{device_ids.size} devices"
  end
end
