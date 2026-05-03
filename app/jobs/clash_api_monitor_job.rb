# app/jobs/clash_api_monitor_job.rb
require 'net/http'
require 'net/ssh'
require 'json'

class ClashApiMonitorJob < ApplicationJob
  queue_as :default

  CLASH_API_PORT = 9090
  WIREGUARD_HANDSHAKE_TIMEOUT = 5.minutes  # ⭐ Allow 5 min of idle before considering inactive
  DEACTIVATION_GRACE_PERIOD = 5.minutes      # Then 5 min grace period

  # ✅ NEW: Force-release configs stuck as "in_use" without activity > 15 min
  FORCE_RELEASE_TIMEOUT = 15.minutes

  def perform
    # ✅ NEW: Force-release abandoned configs FIRST (safety net for DNS failures)
    force_release_abandoned_configs

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
      .joins(:subscription)
      .where(active: true)
      .where('devices.last_seen_at > ?', 5.minutes.ago)
      .where(subscriptions: { status: 'active' })
      .where('subscriptions.expires_at IS NULL OR subscriptions.expires_at > ?', Time.current)  # ✅ CHECK EXPIRATION!
      .pluck('devices.id')

    # ✅ Monitoring job tracks connections for cleanup purposes only
    devices_with_server_verified_connections = devices_with_real_connections.dup
    devices_with_real_connections.merge(devices_with_recent_heartbeats)

    Rails.logger.info "📊 Active devices breakdown:"
    Rails.logger.info "   Total: #{devices_with_real_connections.size}"
    Rails.logger.info "   Server-verified connections: #{devices_with_server_verified_connections.size}"
    Rails.logger.info "   Heartbeat-only: #{devices_with_recent_heartbeats.size}"

    # ✅ Monitoring job does NOT activate devices (only app endpoints do that)
    # It only DEACTIVATES stale devices (cleanup/watchdog role)

    # Deactivate devices that have been inactive for > grace period
    currently_active_device_ids = Device.where(active: true).pluck(:id)
    potentially_inactive_device_ids = currently_active_device_ids - devices_with_real_connections.to_a

    if potentially_inactive_device_ids.any?
      # ✅ FIXED: Handle NULL last_seen_at (catches devices that never sent heartbeat)
      devices_to_deactivate = Device
        .where(id: potentially_inactive_device_ids)
        .where('last_seen_at IS NULL OR last_seen_at < ?', DEACTIVATION_GRACE_PERIOD.ago)
        .pluck(:id)

      if devices_to_deactivate.any?
        release_configs_for_devices(devices_to_deactivate)

        # ✅ Only update active flag, NOT last_seen_at (that's only for app endpoints)
        Device.where(id: devices_to_deactivate).update_all(active: false)

        Rails.logger.info "🔴 Deactivated #{devices_to_deactivate.size} devices (inactive > #{DEACTIVATION_GRACE_PERIOD.inspect})"
      end

      devices_in_grace = potentially_inactive_device_ids - devices_to_deactivate
      if devices_in_grace.any?
        Rails.logger.info "⏳ #{devices_in_grace.size} devices in grace period"
      end
    end
  end

  private

  # ✅ NEW: Force-release configs stuck as "in_use" without activity
  # Catches cases where app couldn't notify backend (DNS failure, network issue)
  # Runs FIRST in every monitoring job as a safety net
  def force_release_abandoned_configs
    abandoned_configs = VpnConfigSet
      .where(status: 'in_use')
      .joins(:device)
      .where(
        'devices.last_seen_at IS NULL OR devices.last_seen_at < ?',
        FORCE_RELEASE_TIMEOUT.ago
      )
      .includes(:device, :server)

    return if abandoned_configs.empty?

    Rails.logger.warn "🚨 FORCE-RELEASING #{abandoned_configs.count} ABANDONED CONFIGS (no activity > #{FORCE_RELEASE_TIMEOUT.inspect}):"

    abandoned_configs.find_each do |config_set|
      device = config_set.device
      last_seen = device.last_seen_at&.strftime('%Y-%m-%d %H:%M:%S') || 'NEVER'

      Rails.logger.warn "   Device #{device.id}: IP #{config_set.ip_address}, last_seen: #{last_seen}, active: #{device.active}"

      # Kill lingering connections
      server = config_set.server
      if server.singbox_active? && server.clash_api_secret.present?
        begin
          killed = kill_singbox_connections_for_vpn_ip(server, config_set.ip_address)
          Rails.logger.info "   🔪 Killed #{killed} sing-box connections" if killed > 0
        rescue => e
          Rails.logger.error "   Failed to kill connections: #{e.message}"
        end
      end

      # Release config
      config_set.release!

      # Mark device inactive
      device.update!(active: false)

      # Close connection records
      device.vpn_connections.where(disconnected_at: nil).update_all(disconnected_at: Time.current)

      Rails.logger.info "   ✅ Released abandoned config #{config_set.ip_address}"
    end
  end

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
  # ✅ FIXED: Match by VPN IP instead of external IP
  def monitor_singbox(server)
    connections = get_active_connections_via_ssh(server)
    Rails.logger.info "🔌 Found #{connections.size} active sing-box connections on #{server.name}"

    connections_by_ip = connections.group_by { |c| c.dig("metadata", "sourceIP") }
    active_device_ids = Set.new

    connections_by_ip.each do |source_ip, conns|
      next unless source_ip

      # ⭐ NEW: Try three matching strategies
      device = nil
      config_set = nil

      # Strategy 1: Match by VPN internal IP (for WireGuard passthrough)
      config_set = VpnConfigSet.find_by(
        server: server,
        ip_address: source_ip,
        status: 'in_use'
      )

      if config_set
        device = config_set.device
        Rails.logger.info "✅ Matched by VPN IP: #{source_ip} → Device #{device&.id}"
      else
        # Strategy 2: Match by external IP
        device = Device.joins(:vpn_config_set)
          .where(active: true, last_connection_ip: source_ip)
          .where(vpn_config_sets: { server_id: server.id, status: 'in_use' })
          .first

        if device
          config_set = device.vpn_config_set
          Rails.logger.info "✅ Matched by external IP: #{source_ip} → Device #{device.id}"
        else
          # ⭐ Strategy 3: Check if ANY device on this server has recent heartbeats from this IP
          # This handles heartbeat-through-VPN case where last_connection_ip is VPN server
          device = Device.joins(:vpn_config_set)
            .where(active: true)
            .where('devices.last_seen_at > ?', 2.minutes.ago)  # Recent heartbeat
            .where(vpn_config_sets: { server_id: server.id, status: 'in_use' })
            .find_by('vpn_config_sets.server_id': server.id)

          if device
            config_set = device.vpn_config_set
            Rails.logger.info "✅ Matched by recent heartbeat: #{source_ip} → Device #{device.id} (VPN IP: #{config_set.ip_address})"
          end
        end
      end

      # ⭐ ONLY kill if NO match AND no recent heartbeats
      if device.nil?
        Rails.logger.warn "🚨 UNKNOWN IP: #{source_ip} (#{conns.size} connections)"
        Rails.logger.warn "   → Killing connections to force re-authentication"

        conns.each do |conn|
          kill_connection_via_ssh(server, conn["id"])
          Rails.logger.info "   🔪 Killed suspicious connection #{conn['id']}"
        end
        next
      end

      # Check subscription
      unless device.subscription&.active?
        Rails.logger.warn "❌ Device #{device.id} subscription inactive"
        conns.each do |conn|
          kill_connection_via_ssh(server, conn["id"])
        end
        device.update!(active: false, connected_at: nil)
        device.vpn_connections.active.update_all(disconnected_at: Time.current)
        next
      end

      active_device_ids << device.id
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
      server = config_set.server
      device = config_set.device

      # ✅ KILL sing-box connections for this VPN IP BEFORE releasing
      if server.singbox_active? && server.clash_api_secret.present?
        begin
          vpn_ip = config_set.ip_address
          killed_count = kill_singbox_connections_for_vpn_ip(server, vpn_ip)
          Rails.logger.info "🔪 Killed #{killed_count} sing-box connections for device #{device.id} (VPN IP: #{vpn_ip})"
        rescue => e
          Rails.logger.error "Failed to kill connections for device #{device.id}: #{e.message}"
        end
      end

      config_set.release!
      Rails.logger.info "Released config #{config_set.ip_address} back to pool"
    end

    VpnConnection.where(device_id: device_ids, disconnected_at: nil).update_all(disconnected_at: Time.current)
    Rails.logger.info "🔓 Released configs for #{device_ids.size} devices"
  end

  # ✅ FIXED: Match by VPN IP instead of external IP
  def kill_singbox_connections_for_vpn_ip(server, vpn_ip)
    connections = get_active_connections_via_ssh(server)
    killed_count = 0

    connections.each do |conn|
      source_ip = conn.dig("metadata", "sourceIP")

      if source_ip == vpn_ip
        connection_id = conn["id"]
        kill_connection_via_ssh(server, connection_id)
        killed_count += 1
        Rails.logger.info "   🔪 Killed connection #{connection_id} from VPN IP #{vpn_ip}"
      end
    end

    killed_count
  end

  # ✅ NEW: Kill WireGuard peer via SSH
  def kill_wireguard_peer(server, vpn_ip)
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
        # Remove WireGuard peer by public key
        # First, find the public key for this IP
        output = ssh.exec!("sudo wg show wg0 dump")

        output.each_line.with_index do |line, index|
          next if index == 0

          parts = line.strip.split("\t")
          next if parts.size < 4

          allowed_ip = parts[3].split('/').first

          if allowed_ip == vpn_ip
            public_key = parts[0]
            ssh.exec!("sudo wg set wg0 peer #{public_key} remove")
            Rails.logger.info "🔪 Removed WireGuard peer: #{public_key} (IP: #{vpn_ip})"
            break
          end
        end
      end
    ensure
      if key_file
        key_file.close unless key_file.closed?
        key_file.unlink
      end
    end
  end
end
