# app/jobs/clash_api_monitor_job.rb
class ClashApiMonitorJob < ApplicationJob
  include SshKeyManager
  queue_as :default

  # Runs every 60 seconds via sidekiq-cron
  # Kills unauthorized connections via Clash API
  CLASH_API_PORT = 9090

  def perform
    Server.where(active: true, singbox_active: true).find_each do |server|
      monitor_server(server)
    end
  end

  private

  def monitor_server(server)
    private_key_path = nil
    private_key_path = write_private_key(server)

    # Open SSH tunnel to Clash API
    Net::SSH.start(server.ip_address, server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|
      # Fetch active connections via Clash API through SSH tunnel
      response = ssh.exec!("curl -s http://127.0.0.1:#{CLASH_API_PORT}/connections")
      connections = JSON.parse(response)

      active_connections = connections["connections"] || []
      Rails.logger.info "Server #{server.name}: #{active_connections.count} active connections"

      active_connections.each do |connection|
        check_connection(ssh, server, connection)
      end
    end
  rescue => e
    Rails.logger.error "ClashApiMonitorJob failed for #{server.name}: #{e.message}"
  ensure
    File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
  end

  def check_connection(ssh, server, connection)
    connection_id = connection["id"]
    # Clash API identifies connections by their metadata
    # The username maps to our client name in sing-box
    username = connection.dig("metadata", "inboundUser")

    return unless username.present?

    # Check if this client has an active session in Rails
    client = Hysteria2Client.find_by(name: username) ||
             ShadowsocksClient.find_by(name: username)

    return unless client

    device = client.device
    is_authorized = device&.active? && device.subscription.active?

    unless is_authorized
      # Kill the unauthorized connection via Clash API
      kill_output = ssh.exec!(
        "curl -s -X DELETE http://127.0.0.1:#{CLASH_API_PORT}/connections/#{connection_id}"
      )
      Rails.logger.warn "Killed unauthorized connection #{connection_id} for client #{username}: #{kill_output}"
    end
  end
end
