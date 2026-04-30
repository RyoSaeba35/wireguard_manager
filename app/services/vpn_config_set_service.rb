# app/services/vpn_config_set_service.rb
class VpnConfigSetService
  include SshKeyManager

  def initialize(server)
    @server = server
  end

  # ==========================================
  # CREATE POOL (One-time setup per server)
  # ==========================================

  def create_pool(pool_size)
    Rails.logger.info "Creating pool of #{pool_size} config sets for #{@server.name}"

    # Track allocated IPs to prevent duplicates (same as WireguardClientCreator)
    allocated_ips = Set.new

    # Generate all config sets in memory first
    config_sets = pool_size.times.map do
      ip = allocate_next_ip(@server, allocated_ips)
      allocated_ips << ip  # Track immediately
      generate_config_set(ip)
    end

    # Batch insert to database
    VpnConfigSet.insert_all(config_sets)

    # Write to server (batch operation)
    write_configs_to_server(config_sets)

    Rails.logger.info "✅ Created #{pool_size} config sets for #{@server.name}"
  end

  # ==========================================
  # RECYCLE STALE CONFIGS (Every 2 hours)
  # ==========================================

  def recycle_stale_configs
    stale_configs = VpnConfigSet.where(server: @server, status: 'used')
                                .where('last_used_at < ?', 5.minutes.ago)

    count = stale_configs.count
    return 0 if count.zero?

    Rails.logger.info "Recycling #{count} stale configs for #{@server.name}"

    begin
      # Rotate credentials AND update server (batch operation)
      rotate_and_update_peers(stale_configs.to_a)

      # ⭐ Only mark as available if rotation succeeded
      stale_configs.update_all(
        status: 'available',
        last_rotated_at: Time.current
      )

      Rails.logger.info "✅ Recycled #{count} configs for #{@server.name}"
      count
    rescue => e
      # Log error but don't mark as available - they'll be retried next run
      Rails.logger.error "Failed to recycle configs for #{@server.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise # Re-raise so job fails and alerts monitoring
    end
  end

  # ==========================================
  # ROTATE ALL CREDENTIALS (Daily at 3 AM)
  # ==========================================

  def rotate_all_credentials
    all_configs = VpnConfigSet.where(server: @server).to_a
    count = all_configs.count

    Rails.logger.info "Rotating credentials for #{count} configs on #{@server.name}"

    rotate_configs_credentials(all_configs)

    VpnConfigSet.where(server: @server).update_all(last_rotated_at: Time.current)

    Rails.logger.info "✅ Rotated #{count} configs for #{@server.name}"
    count
  end

  private

  # ==========================================
  # GENERATE CONFIG SET (Same logic as WireguardClientCreator)
  # ==========================================

  def generate_config_set(ip_address)
    require 'rbnacl'

    # WireGuard keys (EXACTLY as WireguardClientCreator does it)
    private_key_raw = RbNaCl::Random.random_bytes(32)
    private_key = Base64.strict_encode64(private_key_raw)

    public_key_raw = RbNaCl::PrivateKey.new(private_key_raw).public_key.to_bytes
    public_key = Base64.strict_encode64(public_key_raw)

    preshared_key_raw = RbNaCl::Random.random_bytes(32)
    preshared_key = Base64.strict_encode64(preshared_key_raw)

    {
      server_id: @server.id,
      ip_address: ip_address,
      wireguard_private_key: private_key,
      wireguard_public_key: public_key,
      wireguard_preshared_key: preshared_key,
      # sing-box passwords (EXACTLY as SingboxClientCreator does it)
      hysteria2_password: SecureRandom.base64(32),
      shadowsocks_password: SecureRandom.base64(32),
      status: 'available',
      last_rotated_at: Time.current,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  # ==========================================
  # ALLOCATE IP (EXACTLY as WireguardClientCreator)
  # ==========================================

  def allocate_next_ip(server, batch_allocated_ips = Set.new)
    base = "10.155"  # Fixed /16 range

    # Get IPs from database (existing config sets on this server)
    used_ips = VpnConfigSet
      .where(server_id: server.id)
      .pluck(:ip_address)
      .to_set

    # Merge with batch-allocated IPs (prevents duplicates within batch)
    used_ips.merge(batch_allocated_ips)

    # Find next available IP in /16 range
    (0..255).each do |third_octet|
      (2..254).each do |fourth_octet|
        ip = "#{base}.#{third_octet}.#{fourth_octet}"
        return ip unless used_ips.include?(ip)
      end
    end

    raise "No available IPs in #{base}.0.0/16 range for server #{server.name}"
  end

  # ==========================================
  # ROTATE CREDENTIALS (for full rotation)
  # ==========================================

  def rotate_configs_credentials(configs)
    require 'rbnacl'

    updates = configs.map do |config|
      # Generate new WireGuard keys (same as generate_config_set)
      private_key_raw = RbNaCl::Random.random_bytes(32)
      public_key_raw = RbNaCl::PrivateKey.new(private_key_raw).public_key.to_bytes
      preshared_key_raw = RbNaCl::Random.random_bytes(32)

      {
        id: config.id,
        server_id: config.server_id,
        ip_address: config.ip_address,
        wireguard_private_key: Base64.strict_encode64(private_key_raw),
        wireguard_public_key: Base64.strict_encode64(public_key_raw),
        wireguard_preshared_key: Base64.strict_encode64(preshared_key_raw),
        hysteria2_password: SecureRandom.base64(32),
        shadowsocks_password: SecureRandom.base64(32),
        updated_at: Time.current
      }
    end

    # Batch update
    VpnConfigSet.upsert_all(updates, unique_by: :id)

    # Write to server
    write_rotation_to_server(configs)
  end

  # ==========================================
  # ROTATE AND UPDATE PEERS (for recycling - FAST)
  # ==========================================

  # FIXED VERSION of rotate_and_update_peers method
  #
  # THE PROBLEM: The original code used `wg set` + `wg-quick save wg0`
  # which doesn't reliably save AllowedIPs and PresharedKey to the config file.
  #
  # THE SOLUTION: Update the running config with `wg set` (for zero-downtime),
  # then rebuild the entire config file using rebuild_wireguard_config.

  def rotate_and_update_peers(configs)
    require 'rbnacl'

    private_key_path = write_private_key(@server)

    begin
      Net::SSH.start(
        @server.ip_address,
        @server.ssh_user,
        keys: [private_key_path],
        verify_host_key: :never,
        timeout: 600,
        keepalive: true,
        keepalive_interval: 30
      ) do |ssh|
        # ==========================================
        # STEP 1: Generate all new credentials
        # ==========================================
        updates = configs.map do |config|
          old_pub = config.wireguard_public_key

          # Generate new WireGuard keys
          new_priv_raw = RbNaCl::Random.random_bytes(32)
          new_pub = Base64.strict_encode64(RbNaCl::PrivateKey.new(new_priv_raw).public_key.to_bytes)
          new_psk = Base64.strict_encode64(RbNaCl::Random.random_bytes(32))
          new_priv = Base64.strict_encode64(new_priv_raw)

          # Generate new sing-box passwords
          new_hy2_pass = SecureRandom.base64(32)
          new_ss_pass = SecureRandom.base64(32)

          {
            config: config,
            old_pub: old_pub,
            new_pub: new_pub,
            new_psk: new_psk,
            new_priv: new_priv,
            new_hy2_pass: new_hy2_pass,
            new_ss_pass: new_ss_pass
          }
        end

        # ==========================================
        # STEP 2: Update WireGuard RUNNING config (zero-downtime)
        # ==========================================
        wg_commands = updates.map do |u|
          <<~WG_CMD.strip
            wg set wg0 peer #{u[:old_pub]} remove
            echo '#{u[:new_psk]}' | wg set wg0 peer #{u[:new_pub]} preshared-key /dev/stdin allowed-ips #{u[:config].ip_address}/32
          WG_CMD
        end.join("\n")

        # Update running config only (don't use wg-quick save!)
        ssh.exec!(<<~BASH)
          sudo bash -c '#{wg_commands}'
        BASH

        Rails.logger.info "✅ Updated #{configs.size} WireGuard peers (running config)"

        # ==========================================
        # STEP 3: Update database FIRST
        # ==========================================
        db_updates = updates.map do |u|
          {
            id: u[:config].id,
            server_id: u[:config].server_id,
            ip_address: u[:config].ip_address,
            wireguard_private_key: u[:new_priv],
            wireguard_public_key: u[:new_pub],
            wireguard_preshared_key: u[:new_psk],
            hysteria2_password: u[:new_hy2_pass],
            shadowsocks_password: u[:new_ss_pass],
            updated_at: Time.current
          }
        end

        VpnConfigSet.upsert_all(db_updates, unique_by: :id)
        Rails.logger.info "✅ Updated #{configs.size} configs in database"

        # ==========================================
        # STEP 4: Rebuild config FILE with all peers
        # (This ensures AllowedIPs and PresharedKey are properly saved)
        # ==========================================
        all_configs = VpnConfigSet.where(server: @server).to_a
        rebuild_wireguard_config(ssh, all_configs)

        verify_config_sync(ssh, configs.sample([3, configs.size].min))

        Rails.logger.info "✅ Rebuilt WireGuard config file on #{@server.name}"

        # ==========================================
        # STEP 5: Update sing-box if active
        # ==========================================
        if @server.singbox_active?
          update_singbox_users(ssh, updates)
        end
      end
    ensure
      File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
    end
  end

  # ==========================================
  # UPDATE SING-BOX USERS (helper for recycling)
  # ==========================================

  def update_singbox_users(ssh, updates)
    # Read current config
    config_json = ssh.exec!("sudo cat /etc/sing-box/config.json")
    config = JSON.parse(config_json)

    # Find inbounds
    hysteria2_inbound = config["inbounds"].find { |i| i["type"] == "hysteria2" }
    ss_inbound = config["inbounds"].find { |i| i["type"] == "shadowsocks" }

    return unless hysteria2_inbound && ss_inbound

    # Remove old users and add new ones
    updates.each do |u|
      ip = u[:config].ip_address

      # Remove old entries
      hysteria2_inbound["users"].reject! { |user| user["name"] == ip }
      ss_inbound["users"].reject! { |user| user["name"] == ip }

      # Add new entries with new passwords
      hysteria2_inbound["users"] << { "name" => ip, "password" => u[:new_hy2_pass] }
      ss_inbound["users"] << { "name" => ip, "password" => u[:new_ss_pass] }
    end

    # Write updated config using SFTP
    write_singbox_config_to_server(ssh, config)

    # Validate and reload
    check_output = ssh.exec!("sudo sing-box check -c /etc/sing-box/config.json 2>&1")
    if check_output.present? && check_output.include?("FATAL")
      raise "sing-box config validation failed: #{check_output}"
    end

    ssh.exec!("sudo systemctl restart sing-box")
    Rails.logger.info "✅ Updated #{updates.size} sing-box users on #{@server.name}"
  end

  # ==========================================
  # WRITE TO SERVER (SSH)
  # ==========================================

  def write_configs_to_server(config_sets)
    private_key_path = write_private_key(@server)

    begin
      Net::SSH.start(
        @server.ip_address,
        @server.ssh_user,
        keys: [private_key_path],
        verify_host_key: :never,
        timeout: 600,              # ⭐ 10 minute timeout
        keepalive: true,           # ⭐ Keep connection alive
        keepalive_interval: 30     # ⭐ Send keepalive every 30 seconds
      ) do |ssh|
        # ====== WIREGUARD: Write in batches of 500 ======
        config_sets.each_slice(500) do |batch|
          Rails.logger.info "Writing batch of #{batch.size} WireGuard peers to #{@server.name}..."
          write_wireguard_batch(ssh, batch)
        end

        # ====== SING-BOX: Write all users at once ======
        if @server.singbox_active?
          write_all_singbox_users(ssh, config_sets)
          validate_and_reload_singbox(ssh)
        end

        # ====== Reload WireGuard (once, after all batches) ======
        reload_wireguard(ssh)
      end
    ensure
      File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
    end
  end

  def write_rotation_to_server(configs)
    private_key_path = write_private_key(@server)

    begin
      Net::SSH.start(
        @server.ip_address,
        @server.ssh_user,
        keys: [private_key_path],
        verify_host_key: :never,
        timeout: 600,              # ⭐ 10 minute timeout
        keepalive: true,           # ⭐ Keep connection alive
        keepalive_interval: 30     # ⭐ Send keepalive every 30 seconds
      ) do |ssh|
        # Rebuild WireGuard config from all current configs
        all_configs = VpnConfigSet.where(server: @server).to_a
        rebuild_wireguard_config(ssh, all_configs)

        # Rebuild sing-box config if enabled
        if @server.singbox_active?
          rebuild_singbox_config(ssh, all_configs)
          validate_and_reload_singbox(ssh)
        end

        # Reload WireGuard
        reload_wireguard(ssh)
      end
    ensure
      File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
    end
  end

  # ==========================================
  # WIREGUARD BATCH WRITE (EXACTLY as WireguardClientCreator)
  # ==========================================

  def write_wireguard_batch(ssh, config_sets)
    return if config_sets.empty?

    peer_entries = config_sets.map do |config|
      public_key = config[:wireguard_public_key] || config.wireguard_public_key
      preshared_key = config[:wireguard_preshared_key] || config.wireguard_preshared_key
      ip = config[:ip_address] || config.ip_address

      <<~PEER
        ### begin #{ip} ###
        [Peer]
        PublicKey = #{public_key}
        PresharedKey = #{preshared_key}
        AllowedIPs = #{ip}/32
        ### end #{ip} ###
      PEER
    end.join

    # Append to wg0.conf using tee -a (EXACTLY as WireguardClientCreator)
    ssh.exec!(<<~BASH)
      sudo tee -a /etc/wireguard/wg0.conf > /dev/null << 'WIREGUARD_EOF'
      #{peer_entries}
      WIREGUARD_EOF
    BASH

    Rails.logger.info "✅ Wrote #{config_sets.size} WireGuard peers to #{@server.name}"
  end

  def rebuild_wireguard_config(ssh, all_configs)
    require 'net/scp'
    require 'tempfile'

    Rails.logger.info "Rebuilding WireGuard config for #{all_configs.size} peers..."

    # Get base interface config (keep existing settings)
    base_config = ssh.exec!("sudo grep -A 10 '^\[Interface\]' /etc/wireguard/wg0.conf | grep -v '^\[Peer\]'")

    if base_config.nil? || base_config.strip.empty?
      raise "Failed to extract base WireGuard config from server"
    end

    # Generate all peer entries
    peer_entries = all_configs.map do |config|
      <<~PEER
        ### begin #{config.ip_address} ###
        [Peer]
        PublicKey = #{config.wireguard_public_key}
        PresharedKey = #{config.wireguard_preshared_key}
        AllowedIPs = #{config.ip_address}/32
        ### end #{config.ip_address} ###
      PEER
    end.join

    full_config = base_config.strip + "\n\n" + peer_entries

    # ⭐ Write via SCP instead of heredoc (handles large files reliably)
    temp_file = Tempfile.new(['wg0', '.conf'])
    begin
      temp_file.write(full_config)
      temp_file.close

      # Upload via SCP (same reliable method as sing-box)
      ssh.scp.upload!(temp_file.path, "/tmp/wg0_temp.conf")

      # Move to final location with proper permissions
      ssh.exec!("sudo mv /tmp/wg0_temp.conf /etc/wireguard/wg0.conf")
      ssh.exec!("sudo chown root:root /etc/wireguard/wg0.conf")
      ssh.exec!("sudo chmod 600 /etc/wireguard/wg0.conf")

      # Verify the file was written correctly
      verify_result = ssh.exec!("sudo wc -l /etc/wireguard/wg0.conf")
      actual_lines = verify_result.to_i
      expected_lines = full_config.lines.count

      if actual_lines < expected_lines - 5  # Allow small variance
        raise "Config verification failed: expected ~#{expected_lines} lines, got #{actual_lines}"
      end

      Rails.logger.info "✅ Rebuilt WireGuard config with #{all_configs.size} peers (#{actual_lines} lines)"

    ensure
      temp_file.unlink
    end
  end

  def reload_wireguard(ssh)
    # Use sh -c to run the whole pipeline in one sudo context
    result = ssh.exec!("sudo sh -c 'wg-quick strip wg0 | wg syncconf wg0 /dev/stdin'")

    if result && (result.include?("error") || result.include?("Permission denied"))
      raise "WireGuard sync failed: #{result}"
    end

    Rails.logger.info "✅ Synced WireGuard on #{@server.name} (zero downtime)"
  rescue => e
    Rails.logger.error "WireGuard sync failed: #{e.message}, using restart"
    ssh.exec!("sudo systemctl restart wg-quick@wg0")
    Rails.logger.info "⚠️ Restarted WireGuard on #{@server.name} (with downtime)"
  end

  # ==========================================
  # SING-BOX: WRITE ALL USERS AT ONCE (NEW - FIXED)
  # ==========================================

  def write_all_singbox_users(ssh, config_sets)
    Rails.logger.info "Building sing-box config with #{config_sets.size} users..."

    # Read base config
    config_json = ssh.exec!("sudo cat /etc/sing-box/config.json")
    config = JSON.parse(config_json)

    # Find inbounds
    hysteria2_inbound = config["inbounds"].find { |i| i["type"] == "hysteria2" }
    ss_inbound = config["inbounds"].find { |i| i["type"] == "shadowsocks" }

    raise "Hysteria2 inbound not found in sing-box config" unless hysteria2_inbound
    raise "Shadowsocks inbound not found in sing-box config" unless ss_inbound

    # Build complete user lists (all 3000 at once)
    hysteria2_inbound["users"] = config_sets.map do |cs|
      ip = cs[:ip_address] || cs.ip_address
      password = cs[:hysteria2_password] || cs.hysteria2_password
      { "name" => ip, "password" => password }
    end

    ss_inbound["users"] = config_sets.map do |cs|
      ip = cs[:ip_address] || cs.ip_address
      password = cs[:shadowsocks_password] || cs.shadowsocks_password
      { "name" => ip, "password" => password }
    end

    Rails.logger.info "Writing sing-box config to server..."

    # Write config using printf
    write_singbox_config_to_server(ssh, config)

    Rails.logger.info "✅ Wrote #{config_sets.size} sing-box users to #{@server.name}"
  end

  # ==========================================
  # SING-BOX BATCH WRITE (kept for compatibility, not used in create_pool)
  # ==========================================

  def write_singbox_batch(ssh, config_sets)
    return if config_sets.empty?

    # Read current config
    config_json = ssh.exec!("sudo cat /etc/sing-box/config.json")
    config = JSON.parse(config_json)

    # Find inbounds (EXACTLY as SingboxClientCreator)
    hysteria2_inbound = config["inbounds"].find { |i| i["type"] == "hysteria2" }
    raise "Hysteria2 inbound not found in sing-box config" unless hysteria2_inbound

    ss_inbound = config["inbounds"].find { |i| i["type"] == "shadowsocks" }
    raise "Shadowsocks inbound not found in sing-box config" unless ss_inbound

    # Add users
    config_sets.each do |cs|
      ip = cs[:ip_address] || cs.ip_address
      hy2_pass = cs[:hysteria2_password] || cs.hysteria2_password
      ss_pass = cs[:shadowsocks_password] || cs.shadowsocks_password

      hysteria2_inbound["users"] << {
        "name" => ip,
        "password" => hy2_pass
      }

      ss_inbound["users"] << {
        "name" => ip,
        "password" => ss_pass
      }
    end

    # Write config using SFTP
    write_singbox_config_to_server(ssh, config)

    Rails.logger.info "✅ Wrote #{config_sets.size} sing-box users to #{@server.name}"
  end

  def rebuild_singbox_config(ssh, all_configs)
    # Read current config
    config_json = ssh.exec!("sudo cat /etc/sing-box/config.json")
    config = JSON.parse(config_json)

    # Find inbounds
    hysteria2_inbound = config["inbounds"].find { |i| i["type"] == "hysteria2" }
    raise "Hysteria2 inbound not found" unless hysteria2_inbound

    ss_inbound = config["inbounds"].find { |i| i["type"] == "shadowsocks" }
    raise "Shadowsocks inbound not found" unless ss_inbound

    # Rebuild user lists from scratch
    hysteria2_inbound["users"] = all_configs.map do |cs|
      { "name" => cs.ip_address, "password" => cs.hysteria2_password }
    end

    ss_inbound["users"] = all_configs.map do |cs|
      { "name" => cs.ip_address, "password" => cs.shadowsocks_password }
    end

    # Write config using SFTP
    write_singbox_config_to_server(ssh, config)

    Rails.logger.info "✅ Rebuilt sing-box config with #{all_configs.size} users"
  end

  # ==========================================
  # WRITE SING-BOX CONFIG USING SCP (RELIABLE FOR ANY FILE SIZE)
  # ==========================================

  def write_singbox_config_to_server(ssh, config)
    require 'net/scp'
    require 'tempfile'

    # Write JSON to local temp file (400KB for 3000 users)
    temp_file = Tempfile.new(['singbox', '.json'])
    begin
      temp_file.write(JSON.pretty_generate(config))
      temp_file.close

      # Upload via SCP (handles files of any size)
      ssh.scp.upload!(temp_file.path, "/tmp/singbox_temp.json")

      # Move to final location with proper permissions
      ssh.exec!("sudo mv /tmp/singbox_temp.json /etc/sing-box/config.json")
      ssh.exec!("sudo chown root:root /etc/sing-box/config.json")
      ssh.exec!("sudo chmod 644 /etc/sing-box/config.json")
    ensure
      temp_file.unlink
    end
  end

  def validate_and_reload_singbox(ssh)
    check_output = ssh.exec!("sudo sing-box check -c /etc/sing-box/config.json 2>&1")

    if check_output.present? && check_output.include?("FATAL")
      Rails.logger.error "sing-box config validation failed for #{@server.name}: #{check_output}"
      raise "sing-box config validation failed: #{check_output}"
    end

    ssh.exec!("sudo systemctl restart sing-box")
    Rails.logger.info "✅ Restarted sing-box on #{@server.name}"
  end

  def verify_config_sync(ssh, sample_configs)
    sample_configs.each do |config|
      server_config = ssh.exec!("sudo grep -A 3 '### begin #{config.ip_address} ###' /etc/wireguard/wg0.conf")

      unless server_config&.include?(config.wireguard_public_key)
        raise "Config sync verification failed for #{config.ip_address}: public key mismatch"
      end
    end

    Rails.logger.info "✅ Verified config file sync for #{sample_configs.size} random samples"
  end
end
