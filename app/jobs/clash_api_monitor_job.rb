# app/jobs/clash_api_monitor_job.rb
require 'httparty'

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
      Rails.logger.info "🔴 Deactivated #{devices_to_deactivate.size} devices with no real connections"
    end
  end

  private

  def monitor_server(server)
    # Step 1: Build username → source_port mapping from recent logs (OPTIONAL)
    username_to_port = build_username_port_mapping(server)

    if username_to_port.any?
      Rails.logger.info "📊 Username mapping on #{server.name}: #{username_to_port.size} entries"
    else
      Rails.logger.info "📊 No username mapping available for #{server.name}, using fallback"
    end

    # Step 2: Get active connections
    connections = get_active_connections(server)

    Rails.logger.info "🔌 Found #{connections.size} active connections on #{server.name}"

    # Step 3: Match connections to devices
    active_device_ids = Set.new

    connections.each do |conn|
      source_ip = conn.dig("metadata", "sourceIP")
      source_port = conn.dig("metadata", "sourcePort")
      protocol_type = extract_protocol_type(conn.dig("metadata", "type"))

      # Try to find username from logs first
      username = username_to_port["#{source_ip}:#{source_port}"]

      if username
        Rails.logger.info "✅ Matched connection #{source_ip}:#{source_port} → #{username}"

        client = find_client(username)
        if client && client.device
          device = client.device

          if device.subscription&.active?
            active_device_ids << device.id
          else
            kill_connection(server, conn["id"])
            Rails.logger.warn "❌ Killed unauthorized: #{username}"
          end
        end
      else
        # Fallback: match by IP + protocol type
        device = match_device_by_ip_and_protocol(source_ip, protocol_type, server)
        if device
          if device.subscription&.active?
            active_device_ids << device.id
            Rails.logger.info "✅ Matched by fallback: #{source_ip}:#{source_port} → Device #{device.id}"
          else
            kill_connection(server, conn["id"])
            Rails.logger.warn "❌ Killed unauthorized device #{device.id}"
          end
        else
          Rails.logger.warn "⚠️ Unmatched connection: #{source_ip}:#{source_port} (#{protocol_type})"
        end
      end
    end

    Rails.logger.info "✅ #{active_device_ids.size} active devices on #{server.name}"
    active_device_ids.to_a

  rescue => e
    Rails.logger.error "ClashApiMonitorJob failed for #{server.name}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    []
  end

  def build_username_port_mapping(server)
    response = HTTParty.get(
      "http://#{server.ip_address}:#{CLASH_API_PORT}/logs",
      headers: { "Authorization" => "Bearer #{server.clash_api_secret}" },
      timeout: 3,
      read_timeout: 3
    )

    return {} unless response.success?

    mapping = {}

    response.body.split("\n").each do |line|
      begin
        log = JSON.parse(line)
        payload = log["payload"]
        next unless payload

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

    mapping

  rescue Net::ReadTimeout, Net::OpenTimeout => e
    Rails.logger.warn "Logs endpoint timeout (expected for streaming endpoint): #{e.message}"
    {}
  rescue => e
    Rails.logger.error "Failed to build username mapping: #{e.class} - #{e.message}"
    {}
  end

  def get_active_connections(server)
    response = HTTParty.get(
      "http://#{server.ip_address}:#{CLASH_API_PORT}/connections",
      headers: { "Authorization" => "Bearer #{server.clash_api_secret}" },
      timeout: 10
    )

    return [] unless response.success?

    response.parsed_response["connections"] || []
  rescue => e
    Rails.logger.error "Failed to get connections: #{e.class} - #{e.message}"
    []
  end

  def match_device_by_ip_and_protocol(source_ip, protocol_type, server)
    Device.where(active: true)
          .where(last_connection_ip: source_ip)
          .where(last_protocol_type: protocol_type)
          .joins(:subscription)
          .where(subscriptions: { server_id: server.id })
          .first
  end

  def extract_protocol_type(type_string)
    return nil unless type_string

    if type_string.include?("shadowsocks")
      "shadowsocks"
    elsif type_string.include?("hysteria2")
      "hysteria2"
    else
      "unknown"
    end
  end

  def find_client(username)
    Hysteria2Client.find_by(name: username) ||
      ShadowsocksClient.find_by(name: username) ||
      WireguardClient.find_by(name: username)
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

  def free_clients_for_devices(device_ids)
    return if device_ids.empty?

    Hysteria2Client.where(device_id: device_ids).update_all(device_id: nil)
    ShadowsocksClient.where(device_id: device_ids).update_all(device_id: nil)
    WireguardClient.where(device_id: device_ids).update_all(device_id: nil)

    Rails.logger.info "🔓 Freed clients for #{device_ids.size} inactive devices"
  end
end
