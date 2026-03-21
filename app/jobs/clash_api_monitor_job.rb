# app/jobs/clash_api_monitor_job.rb
class ClashApiMonitorJob < ApplicationJob
  queue_as :default

  CLASH_API_PORT = 9090

  def perform
    Server.where(active: true, singbox_active: true).find_each do |server|
      monitor_server(server)
    end
  end

  private

  def monitor_server(server)
    response = HTTParty.get(
      "http://#{server.ip_address}:#{CLASH_API_PORT}/connections",
      headers: { "Authorization" => "Bearer #{server.clash_api_secret}" },
      timeout: 5
    )

    return unless response.success?

    connections = response.parsed_response["connections"] || []
    Rails.logger.info "Server #{server.name}: #{connections.count} active connections"

    # Track username → [connection_ids] for duplicate detection
    username_connections = {}

    connections.each do |connection|
      username = connection.dig("metadata", "inboundUser")
      next unless username.present?

      # Authorization check first
      authorized = check_connection(server, connection)

      # Only track authorized connections for duplicate detection
      if authorized
        username_connections[username] ||= []
        username_connections[username] << connection["id"]
      end
    end

    # Kill duplicate connections (same client connected more than once)
    enforce_single_connection(server, username_connections)

  rescue => e
    Rails.logger.error "ClashApiMonitorJob failed for #{server.name}: #{e.message}"
  end

  # Returns true if authorized, false if killed
  def check_connection(server, connection)
    connection_id = connection["id"]
    username = connection.dig("metadata", "inboundUser")

    return false unless username.present?

    client = Hysteria2Client.find_by(name: username) ||
             ShadowsocksClient.find_by(name: username)

    return false unless client

    device = client.device
    is_authorized = device&.active? && device.subscription.active?

    unless is_authorized
      kill_connection(server, connection_id)
      Rails.logger.warn "Killed unauthorized connection #{connection_id} for user #{username}"
      return false
    end

    true
  end

  def enforce_single_connection(server, username_connections)
    username_connections.each do |username, connection_ids|
      next if connection_ids.size <= 1

      # Keep the first, kill the rest
      connection_ids[1..].each do |connection_id|
        kill_connection(server, connection_id)
        Rails.logger.warn "Killed duplicate connection #{connection_id} for #{username}"
      end
    end
  end

  def kill_connection(server, connection_id)
    HTTParty.delete(
      "http://#{server.ip_address}:#{CLASH_API_PORT}/connections/#{connection_id}",
      headers: { "Authorization" => "Bearer #{server.clash_api_secret}" },
      timeout: 5
    )
  end
end
