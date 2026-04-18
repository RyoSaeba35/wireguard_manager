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
  # RECYCLE STALE CONFIGS (Every 15 minutes)
  # ==========================================

  def recycle_stale_configs
    # Find configs that have been in "used" state for >15 minutes
    stale_configs = VpnConfigSet.where(server: @server, status: 'used')
                                .where('last_used_at < ?', 15.minutes.ago)

    count = stale_configs.count
    return 0 if count.zero?

    Rails.logger.info "Recycling #{count} stale configs for #{@server.name}"

    # Rotate credentials
    rotate_configs_credentials(stale_configs.to_a)

    # Mark as available
    stale_configs.update_all(
      status: 'available',
      last_rotated_at: Time.current
    )

    Rails.logger.info "✅ Recycled #{count} configs for #{@server.name}"
    count
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
  # ROTATE CREDENTIALS
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
        timeout: 600,
        keepalive: true,
        keepalive_interval: 30
      ) do |ssh|
        # Write WireGuard configs
        write_wireguard_batch(ssh, config_sets)

        # Write sing-box configs if enabled
        if @server.singbox_active?
          write_singbox_batch(ssh, config_sets)
          validate_and_reload_singbox(ssh)
        end

        # Reload WireGuard (no downtime)
        reload_wireguard(ssh)
      end
    ensure
      File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
    end
  end

  def write_rotation_to_server(configs)
    # Rebuild entire config files after rotation
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
        # #{ip}
        [Peer]
        PublicKey = #{public_key}
        PresharedKey = #{preshared_key}
        AllowedIPs = #{ip}/32

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
    # Get base interface config (keep existing settings)
    base_config = ssh.exec!("sudo grep -A 10 '^\[Interface\]' /etc/wireguard/wg0.conf | grep -v '^\[Peer\]'")

    # Generate all peer entries
    peer_entries = all_configs.map do |config|
      <<~PEER
        # #{config.ip_address}
        [Peer]
        PublicKey = #{config.wireguard_public_key}
        PresharedKey = #{config.wireguard_preshared_key}
        AllowedIPs = #{config.ip_address}/32

      PEER
    end.join

    full_config = base_config.strip + "\n\n" + peer_entries

    # Write complete config
    ssh.exec!(<<~BASH)
      sudo tee /etc/wireguard/wg0.conf > /dev/null << 'WIREGUARD_EOF'
      #{full_config}
      WIREGUARD_EOF
    BASH

    Rails.logger.info "✅ Rebuilt WireGuard config with #{all_configs.size} peers"
  end

  def reload_wireguard(ssh)
    # No-downtime reload (better than restart for production)
    ssh.exec!("sudo systemctl restart wg-quick@wg0")
    Rails.logger.info "✅ Reloaded WireGuard on #{@server.name}"
  end

  # ==========================================
  # SING-BOX BATCH WRITE (EXACTLY as SingboxClientCreator)
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

    # Write config (EXACTLY as SingboxClientCreator)
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

    ss_inbound = config["inbounds"].find { |i| i["type"] == "shadowsocks" }  # ✅ FIXED TYPO
    raise "Shadowsocks inbound not found" unless ss_inbound

    # Rebuild user lists from scratch
    hysteria2_inbound["users"] = all_configs.map do |cs|
      { "name" => cs.ip_address, "password" => cs.hysteria2_password }
    end

    ss_inbound["users"] = all_configs.map do |cs|
      { "name" => cs.ip_address, "password" => cs.shadowsocks_password }
    end

    # Write config
    write_singbox_config_to_server(ssh, config)

    Rails.logger.info "✅ Rebuilt sing-box config with #{all_configs.size} users"
  end

  def write_singbox_config_to_server(ssh, config)
    # EXACTLY as SingboxClientCreator
    updated_config = JSON.pretty_generate(config)
    ssh.exec!("sudo tee /etc/sing-box/config.json > /dev/null << 'SINGBOX_EOF'\n#{updated_config}\nSINGBOX_EOF")
  end

  def validate_and_reload_singbox(ssh)
    # EXACTLY as SingboxClientCreator
    check_output = ssh.exec!("sudo sing-box check -c /etc/sing-box/config.json 2>&1")

    if check_output.present? && check_output.include?("FATAL")
      Rails.logger.error "sing-box config validation failed for #{@server.name}: #{check_output}"
      raise "sing-box config validation failed: #{check_output}"
    end

    ssh.exec!("sudo systemctl reload sing-box")  # reload, NOT restart!
    Rails.logger.info "✅ Reloaded sing-box on #{@server.name}"
  end
end
