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
    # Step 1: Build username → source_port mapping from recent logs
    username_to_port = build_username_port_mapping(server)

    Rails.logger.info "📊 Username mapping on #{server.name}: #{username_to_port.inspect}"

    # Step 2: Get active connections
    connections = get_active_connections(server)

    # Step 3: Match connections to usernames using source port
    active_device_ids = Set.new

    connections.each do |conn|
      source_ip = conn.dig("metadata", "sourceIP")
      source_port = conn.dig("metadata", "sourcePort")
      protocol_type = extract_protocol_type(conn.dig("metadata", "type"))

      # Find username for this source port
      username = username_to_port["#{source_ip}:#{source_port}"]

      if username
        Rails.logger.info "✅ Matched connection #{source_ip}:#{source_port} → #{username}"

        # Find device for this username
        client = find_client(username)
        next unless client

        device = client.device
        next unless device

        # Check authorization
        unless device.subscription&.active?
          kill_connection(server, conn["id"])
          Rails.logger.warn "❌ Killed unauthorized: #{username}"
          next
        end

        active_device_ids << device.id
      else
        # No username found in logs - try to infer from database
        Rails.logger.warn "⚠️ Connection #{source_ip}:#{source_port} has no username in logs"

        # Fallback: match by IP + protocol type
        device = match_device_by_ip_and_protocol(source_ip, protocol_type, server)
        if device && device.subscription&.active?
          active_device_ids << device.id
        end
      end
    end

    active_device_ids.to_a

  rescue => e
    Rails.logger.error "ClashApiMonitorJob failed for #{server.name}: #{e.message}"
    []
  end

  def build_username_port_mapping(server)
    response = HTTParty.get(
      "http://#{server.ip_address}:#{CLASH_API_PORT}/logs",
      headers: { "Authorization" => "Bearer #{server.clash_api_secret}" },
      timeout: 2,
      read_timeout: 2
    )

    return {} unless response.success?

    mapping = {}

    # Parse log lines (each line is JSON)
    response.body.split("\n").each do |line|
      begin
        log = JSON.parse(line)
        payload = log["payload"]
        next unless payload

        # Extract: "inbound connection from 176.143.53.46:65201" and "[NAUIZ_2]"
        # Pattern: inbound connection from IP:PORT ... [USERNAME]
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

  rescue => e
    Rails.logger.error "Failed to build username mapping: #{e.message}"
    {}
  end

  def get_active_connections(server)
    response = HTTParty.get(
      "http://#{server.ip_address}:#{CLASH_API_PORT}/connections",
      headers: { "Authorization" => "Bearer #{server.clash_api_secret}" },
      timeout: 5
    )

    return [] unless response.success?

    response.parsed_response["connections"] || []
  end

  def match_device_by_ip_and_protocol(source_ip, protocol_type, server)
    # Fallback: if we can't identify from logs, match by IP + protocol
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
