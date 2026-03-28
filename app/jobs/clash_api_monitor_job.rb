# app/jobs/clash_api_monitor_job.rb
require 'net/http'
require 'net/ssh'
require 'json'

class ClashApiMonitorJob < ApplicationJob
  include SshKeyManager

  queue_as :default

  CLASH_API_PORT = 9090
  LOG_FILE_PATH = "/var/log/sing-box/connections.log"
  LINES_TO_READ = 1000

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
    username_to_port = read_log_file(server)

    Rails.logger.info "📊 Found #{username_to_port.size} username mappings from logs"

    connections = get_active_connections(server)

    Rails.logger.info "🔌 Found #{connections.size} active connections"

    detect_password_theft(username_to_port, connections, server)

    active_device_ids = Set.new
    matched_connections = Set.new  # NEW: Track unique IP:port combinations

    connections.each do |conn|
      source_ip = conn.dig("metadata", "sourceIP")
      source_port = conn.dig("metadata", "sourcePort")
      source_key = "#{source_ip}:#{source_port}"  # NEW: Unique key

      username = username_to_port[source_key]

      if username
        # NEW: Skip if we already processed this IP:port
        if matched_connections.include?(source_key)
          next
        end
        matched_connections.add(source_key)  # NEW: Mark as processed

        client = find_client(username)

        # Kill orphan connections (explicitly disconnected)
        if client && client.device_id.nil?
          Rails.logger.warn "🧹 Killing orphan connection: #{username} (user disconnected)"
          kill_connection(server, conn["id"])
          next
        end

        # Skip locked clients
        if client&.locked_at
          Rails.logger.warn "⚠️ Skipping locked client: #{username}"
          kill_connection(server, conn["id"])
          next
        end

        next unless client&.device

        device = client.device

        unless device.subscription&.active?
          kill_connection(server, conn["id"])
          Rails.logger.warn "❌ Killed unauthorized: #{username}"
          next
        end

        Rails.logger.info "✅ Matched: #{source_key} → #{username}"  # Now logs once per unique connection
        active_device_ids << device.id
      else
        # Also deduplicate "No username" warnings
        unless matched_connections.include?(source_key)
          Rails.logger.warn "⚠️ No username for: #{source_key}"
          matched_connections.add(source_key)
        end
      end
    end

    Rails.logger.info "✅ #{active_device_ids.size} active devices"

    # Mark devices with real connections as active
    if active_device_ids.any?
      Device.where(id: active_device_ids).update_all(
        active: true,
        last_seen_at: Time.current
      )
    end

    # Deactivate devices claiming to be active but with no connection
    currently_active_device_ids = Device.where(active: true).pluck(:id)
    devices_to_deactivate = currently_active_device_ids - active_device_ids.to_a

    if devices_to_deactivate.any?
      free_clients_for_devices(devices_to_deactivate)
      Device.where(id: devices_to_deactivate).update_all(
        active: false,
        last_seen_at: Time.current
      )
      Rails.logger.info "🔴 Deactivated #{devices_to_deactivate.size} devices"
    end

    active_device_ids.to_a
  end

  def detect_password_theft(username_to_port, connections, server)
    connections_by_username = {}

    connections.each do |conn|
      source_ip = conn.dig("metadata", "sourceIP")
      source_port = conn.dig("metadata", "sourcePort")
      username = username_to_port["#{source_ip}:#{source_port}"]

      next unless username

      connections_by_username[username] ||= []
      connections_by_username[username] << {
        ip: source_ip,
        port: source_port,
        connection_id: conn["id"]
      }
    end

    connections_by_username.each do |username, conns|
      unique_ips = conns.map { |c| c[:ip] }.uniq

      # Skip if only 1 IP (normal case)
      next if unique_ips.size == 1

      Rails.logger.info "🔍 Checking #{username}: #{unique_ips.size} different IPs"

      # Get geolocation for each IP
      geolocations = unique_ips.map do |ip|
        geo = get_geolocation(ip)
        { ip: ip, geo: geo }
      end

      countries = geolocations.map { |g| g[:geo][:country] }.uniq.compact

      if countries.size > 1
        # CRITICAL: Password used in multiple countries simultaneously!
        Rails.logger.error "🚨 CRITICAL PASSWORD THEFT: #{username} used in #{countries.join(' + ')} simultaneously!"
        Rails.logger.error "   IPs: #{geolocations.map { |g| "#{g[:ip]} (#{g[:geo][:country]}, #{g[:geo][:city]})" }.join(' | ')}"

        # Kill all connections for this username
        conns.each do |c|
          kill_connection_by_connection_id(server, c[:connection_id])
        end

        # Lock the client
        client = find_client(username)
        if client
          client.update!(
            locked_at: Time.current,
            locked_reason: "Password used from #{countries.join(', ')} simultaneously at #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}"
          )

          # Send critical alert
          AdminMailer.password_theft_alert(
            username: username,
            geolocations: geolocations,
            client: client
          ).deliver_now

          Rails.logger.error "🔒 Locked client #{username}"
        end
      else
        # Same country, different IPs - probably legitimate (WiFi switching)
        Rails.logger.info "ℹ️ #{username} using #{unique_ips.size} IPs in #{countries.first || 'Unknown'} (likely network switching)"
      end
    end
  rescue => e
    Rails.logger.error "Password theft detection failed: #{e.message}"
  end

  def get_geolocation(ip)
    # Skip private/local IPs
    return { country: 'Local', city: 'Private Network' } if ip.start_with?('192.168.', '10.', '172.16.', '127.')

    # Check cache first (avoid API rate limits)
    cache_key = "geolocation:#{ip}"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    # Use ipapi.co (free tier: 1000 requests/day)
    response = HTTParty.get("https://ipapi.co/#{ip}/json/", timeout: 3)

    geo = if response.success? && response['country']
      {
        country: response['country_name'] || 'Unknown',
        city: response['city'] || 'Unknown',
        country_code: response['country'] || 'XX'
      }
    else
      { country: 'Unknown', city: 'Unknown', country_code: 'XX' }
    end

    # Cache for 24 hours
    Rails.cache.write(cache_key, geo, expires_in: 24.hours)
    geo
  rescue => e
    Rails.logger.warn "Geolocation failed for #{ip}: #{e.message}"
    { country: 'Unknown', city: 'Unknown', country_code: 'XX' }
  end

  def read_log_file(server)
    mapping = {}
    private_key_path = nil

    begin
      private_key_path = write_private_key(server)

      Net::SSH.start(server.ip_address, server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|
        log_content = ssh.exec!("tail -n #{LINES_TO_READ} #{LOG_FILE_PATH}")

        # Group lines by connection ID
        connections_by_id = {}

        log_content.each_line do |line|
          conn_id_match = line.match(/\[(\d+)\s+\d+ms\]/)
          next unless conn_id_match

          conn_id = conn_id_match[1]
          connections_by_id[conn_id] ||= []
          connections_by_id[conn_id] << line
        end

        # Match IP:PORT with USERNAME for same connection ID
        connections_by_id.each do |conn_id, lines|
          ip = nil
          port = nil
          username = nil

          lines.each do |line|
            if ip_port_match = line.match(/from\s+([\d\.]+):(\d+)/)
              ip = ip_port_match[1]
              port = ip_port_match[2]
            end

            if username_match = line.match(/\[([A-Z0-9_]+)\]/)
              username = username_match[1]
            end
          end

          if ip && port && username
            mapping["#{ip}:#{port}"] = username
          end
        end
      end
    rescue => e
      Rails.logger.error "Failed to read log file: #{e.message}"
    ensure
      File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
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

  alias_method :kill_connection_by_connection_id, :kill_connection

  def free_clients_for_devices(device_ids)
    return if device_ids.empty?

    Hysteria2Client.where(device_id: device_ids).update_all(device_id: nil)
    ShadowsocksClient.where(device_id: device_ids).update_all(device_id: nil)
    WireguardClient.where(device_id: device_ids).update_all(device_id: nil)

    Rails.logger.info "🔓 Freed clients for #{device_ids.size} devices"
  end
end
