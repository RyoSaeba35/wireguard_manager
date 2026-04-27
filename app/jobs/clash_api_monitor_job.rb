# app/jobs/clash_api_monitor_job.rb
require 'net/http'
require 'net/ssh'
require 'json'

class ClashApiMonitorJob < ApplicationJob
  queue_as :default

  CLASH_API_PORT = 9090
  WIREGUARD_HANDSHAKE_TIMEOUT = 5.minutes  # ⭐ Allow 5 min of idle before considering inactive
  DEACTIVATION_GRACE_PERIOD = 5.minutes      # Then 5 min grace period

  def perform
    devices_with_real_connections = Set.new

    Server.active.healthy.find_each do |server|
      # ⭐ Monitor WireGuard (primary protocol)
      wg_devices = monitor_wireguard(server)
      devices_with_real_connections.merge(wg_devices)

      # ⭐ Monitor sing-box (for Hysteria2/Shadowsocks users)
      if server.singbox_active? && server.clash_api_secret.present?
        singbox_devices = monitor_singbox(server)
        devices_with_real_connections.merge(singbox_devices)
      end
    end

    # ✅ ALSO trust app heartbeats (backup for server monitoring failures)
    devices_with_recent_heartbeats = Device
      .where(active: true)
      .where('last_seen_at > ?', 5.minutes.ago)  # Heartbeat every 10s, 5min grace for Doze mode
      .pluck(:id)

    devices_with_real_connections.merge(devices_with_recent_heartbeats)

    Rails.logger.info "📊 Active devices breakdown:"
    Rails.logger.info "   Total: #{devices_with_real_connections.size}"
    Rails.logger.info "   Heartbeat-detected: #{devices_with_recent_heartbeats.size}"

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

  # ⭐ Monitor WireGuard connections via SSH
  def monitor_wireguard(server)
    active_device_ids = Set.new
    key_file = nil

    begin
      # Write SSH key to temp file
      key_file = Tempfile.new(['ssh_key', '.pem'])
      key_content = server.ssh_private_key.strip
      key_content += "\n" unless key_content.end_with?("\n")
      key_file.write(key_content)
      key_file.close
      File.chmod(0600, key_file.path)

      Net::SSH.start(
        server.ip_address,
        server.ssh_user,
        keys: [key_file.path],
        auth_methods: ['publickey'],
        verify_host_key: :never,
        non_interactive: true,
        timeout: 10
      ) do |ssh|
        # Get WireGuard peer info
        output = ssh.exec!("sudo wg show wg0 dump")

        output.each_line.with_index do |line, index|
          next if index == 0 # Skip interface header line

          parts = line.strip.split("\t")
          next if parts.size < 5

          public_key = parts[0]
          latest_handshake = parts[4].to_i

          # ⭐ Active if handshake within WIREGUARD_HANDSHAKE_TIMEOUT
          if latest_handshake > 0 && Time.at(latest_handshake) > WIREGUARD_HANDSHAKE_TIMEOUT.ago
            allowed_ip = parts[3].split('/').first # "10.155.0.5/32" -> "10.155.0.5"

            # Find config by IP
            config_set = VpnConfigSet.find_by(
              server: server,
              ip_address: allowed_ip,
              status: 'in_use'
            )

            next unless config_set

            device = config_set.device
            next unless device&.subscription&.active?

            Rails.logger.info "✅ WireGuard active: #{allowed_ip} → Device #{device.id}"
            active_device_ids << device.id
          end
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      Rails.logger.error "SSH auth failed for #{server.name}: #{e.message}"
    rescue => e
      Rails.logger.error "Failed to monitor WireGuard on #{server.name}: #{e.message}"
    ensure
      if key_file
        key_file.close unless key_file.closed?
        key_file.unlink
      end
    end

    Rails.logger.info "✅ #{active_device_ids.size} active WireGuard devices on #{server.name}"
    active_device_ids.to_a
  end

  # ⭐ Monitor sing-box connections via Clash API (accessed via SSH)
  def monitor_singbox(server)
    connections = get_active_connections_via_ssh(server)
    Rails.logger.info "🔌 Found #{connections.size} active sing-box connections on #{server.name}"

    # Group connections by external IP
    connections_by_ip = connections.group_by { |c| c.dig("metadata", "sourceIP") }

    active_device_ids = Set.new

    connections_by_ip.each do |source_ip, conns|
      next unless source_ip

      # Find devices by external IP (regardless of active status for conflict detection)
      devices = Device.joins(:vpn_config_set)
                      .where(last_connection_ip: source_ip)
                      .where(vpn_config_sets: { server_id: server.id })
                      .limit(conns.size)

      if devices.empty?
        Rails.logger.warn "⚠️ No devices found for external IP: #{source_ip} (#{conns.size} connections)"
        next
      end

      devices.each do |device|
        unless device.subscription&.active?
          Rails.logger.warn "❌ Device #{device.id} subscription inactive"
          next
        end

        config_set = device.vpn_config_set

        # ✅ SECURITY CHECK: Detect stale credential conflicts
        if config_set.status == 'in_use' && config_set.device_id != device.id
          Rails.logger.error "🚨 CONFLICT DETECTED: Config #{config_set.ip_address} is in_use by device #{config_set.device_id}, but connection detected from device #{device.id}"
          Rails.logger.error "   External IP: #{source_ip} - This indicates stale credentials being used!"
          Rails.logger.error "   The app should fetch fresh credentials via /api/connect"

          # Don't self-heal - this is an unauthorized connection using stale credentials
          # Let the app call /api/connect for fresh credentials
          next
        end

        # ✅ Safe to self-heal - this was the original owner or config is available
        unless device.active?
          Rails.logger.info "🔄 Self-healing: Reactivating device #{device.id}"
          device.update!(active: true, last_seen_at: Time.current)
        end

        if config_set.status != 'in_use'
          Rails.logger.info "🔄 Self-healing: Reclaiming config #{config_set.ip_address} for original owner device #{device.id}"
          config_set.update!(status: 'in_use', device_id: device.id)
        end

        Rails.logger.info "✅ sing-box active: External IP #{source_ip} → Device #{device.id} (VPN IP: #{config_set.ip_address})"
        active_device_ids << device.id
      end
    end

    Rails.logger.info "✅ #{active_device_ids.size} active sing-box devices on #{server.name}"
    active_device_ids.to_a
  end

  # ✅ Access Clash API via SSH tunnel (secure - no exposed port)
  def get_active_connections_via_ssh(server)
    key_file = nil

    begin
      # Write SSH key to temp file
      key_file = Tempfile.new(['ssh_key', '.pem'])
      key_content = server.ssh_private_key.strip
      key_content += "\n" unless key_content.end_with?("\n")
      key_file.write(key_content)
      key_file.close
      File.chmod(0600, key_file.path)

      Net::SSH.start(
        server.ip_address,
        server.ssh_user,
        keys: [key_file.path],
        auth_methods: ['publickey'],
        verify_host_key: :never,
        non_interactive: true,
        timeout: 10
      ) do |ssh|
        # Execute curl command on the remote server to access localhost Clash API
        command = "curl -s -H 'Authorization: Bearer #{server.clash_api_secret}' http://127.0.0.1:#{CLASH_API_PORT}/connections"
        output = ssh.exec!(command)

        return [] if output.blank?

        data = JSON.parse(output)
        return data["connections"] || []
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse Clash API response from #{server.name}: #{e.message}"
      return []
    rescue Net::SSH::AuthenticationFailed => e
      Rails.logger.error "SSH auth failed for #{server.name}: #{e.message}"
      return []
    rescue => e
      Rails.logger.error "Failed to get connections from #{server.name}: #{e.message}"
      return []
    ensure
      if key_file
        key_file.close unless key_file.closed?
        key_file.unlink
      end
    end
  end

  def kill_connection_via_ssh(server, connection_id)
    key_file = nil

    begin
      key_file = Tempfile.new(['ssh_key', '.pem'])
      key_content = server.ssh_private_key.strip
      key_content += "\n" unless key_content.end_with?("\n")
      key_file.write(key_content)
      key_file.close
      File.chmod(0600, key_file.path)

      Net::SSH.start(
        server.ip_address,
        server.ssh_user,
        keys: [key_file.path],
        auth_methods: ['publickey'],
        verify_host_key: :never,
        non_interactive: true,
        timeout: 10
      ) do |ssh|
        command = "curl -s -X DELETE -H 'Authorization: Bearer #{server.clash_api_secret}' http://127.0.0.1:#{CLASH_API_PORT}/connections/#{connection_id}"
        ssh.exec!(command)
        Rails.logger.info "🔪 Killed connection #{connection_id} on #{server.name}"
      end
    rescue => e
      Rails.logger.error "Failed to kill connection #{connection_id} on #{server.name}: #{e.message}"
    ensure
      if key_file
        key_file.close unless key_file.closed?
        key_file.unlink
      end
    end
  end

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
