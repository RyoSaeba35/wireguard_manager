require 'tempfile'
require 'rbnacl'

module WireguardClientCreator
  include SshKeyManager

  # ⭐ Batch create multiple clients (FAST)
  def create_clients_batch(ssh, client_names, subscription, server)
    Rails.logger.info "Batch creating #{client_names.size} clients for #{subscription.name}"

    # ⭐ FIX: Track allocated IPs within this batch
    allocated_ips = Set.new

    # Generate all configs locally
    configs = client_names.map do |name|
      ip = allocate_next_ip(server, allocated_ips)  # ✅ Pass allocated_ips
      allocated_ips << ip  # ✅ Track immediately
      generate_client_config(name, ip)
    end

    # Write all peers to server in ONE operation
    add_peers_to_wireguard(ssh, configs)

    # Save to database and generate config files
    configs.each do |config|
      save_client_to_db(config, subscription, server)
    end

    Rails.logger.info "✅ Created #{configs.size} clients successfully"
    configs.size
  end

  # ⭐ Single client creation (kept for backward compatibility)
  def create_client_on_server(ssh, client_name, subscription, server)
    Rails.logger.info "Creating client #{client_name} on #{server.name}..."

    if subscription.wireguard_clients.exists?(name: client_name)
      Rails.logger.info "Skipping existing client: #{client_name}"
      return true
    end

    ip = allocate_next_ip(server)  # No batch IPs needed
    config = generate_client_config(client_name, ip)

    add_peers_to_wireguard(ssh, [config])
    save_client_to_db(config, subscription, server)

    true
  end

  private

  # ⭐ Generate WireGuard keys on backend (like sing-box passwords)
  def generate_client_config(name, ip_address)
    # Generate private key (32 random bytes)
    private_key_raw = RbNaCl::Random.random_bytes(32)
    private_key = Base64.strict_encode64(private_key_raw)

    # Generate public key using Curve25519
    public_key_raw = RbNaCl::PrivateKey.new(private_key_raw).public_key.to_bytes
    public_key = Base64.strict_encode64(public_key_raw)

    # Generate preshared key (32 random bytes)
    preshared_key_raw = RbNaCl::Random.random_bytes(32)
    preshared_key = Base64.strict_encode64(preshared_key_raw)

    {
      name: name,
      private_key: private_key,
      public_key: public_key,
      preshared_key: preshared_key,
      ip_address: ip_address
    }
  end

  # ⭐ Allocate next available IP from 10.155.0.0/16 range
  # batch_allocated_ips: IPs already allocated in current batch (optional)
  def allocate_next_ip(server, batch_allocated_ips = Set.new)
    base = "10.155"

    # Get IPs from database
    used_ips = WireguardClient
      .joins(:subscription)
      .where(subscriptions: { server_id: server.id })
      .pluck(:ip_address)
      .to_set

    # ⭐ Merge with batch-allocated IPs (prevents duplicates within batch)
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

  # Add peers to WireGuard config (replaces pivpn -a)
  def add_peers_to_wireguard(ssh, configs)
    return if configs.empty?

    peer_entries = configs.map do |config|
      <<~PEER
        ### begin #{config[:name]} ###
        [Peer]
        PublicKey = #{config[:public_key]}
        PresharedKey = #{config[:preshared_key]}
        AllowedIPs = #{config[:ip_address]}/16
        ### end #{config[:name]} ###
      PEER
    end.join

    ssh.exec!(<<~BASH)
      sudo tee -a /etc/wireguard/wg0.conf > /dev/null << 'WIREGUARD_EOF'
      #{peer_entries}
      WIREGUARD_EOF
    BASH

    ssh.exec!("sudo wg syncconf wg0 <(wg-quick strip wg0)")

    Rails.logger.info "✅ Added #{configs.size} peer(s) to WireGuard and reloaded"
  end

  # Save client to database and generate config file
  def save_client_to_db(config, subscription, server)
    wireguard_client = subscription.wireguard_clients.create!(
      name: config[:name],
      private_key: config[:private_key],
      public_key: config[:public_key],
      preshared_key: config[:preshared_key],
      ip_address: config[:ip_address],
      expires_at: subscription.expires_at,
      status: "active"
    )

    config_content = generate_config_file_content(wireguard_client, server)

    wireguard_client.config_file.attach(
      io: StringIO.new(config_content),
      filename: "#{wireguard_client.name}.conf",
      content_type: 'application/octet-stream'
    )

    generate_and_attach_qr_code(wireguard_client, config_content)

    Rails.logger.info "Saved client #{config[:name]} to database"
  end

  # Generate WireGuard config file content
  def generate_config_file_content(client, server)
    <<~CONFIG
      [Interface]
      PrivateKey = #{client.private_key}
      Address = #{client.ip_address}/16
      DNS = 1.1.1.1

      [Peer]
      PublicKey = #{server.wireguard_public_key}
      PresharedKey = #{client.preshared_key}
      Endpoint = #{server.ip_address}:#{server.wireguard_port}
      AllowedIPs = 0.0.0.0/0, ::0/0
      PersistentKeepalive = 25
    CONFIG
  end

  def generate_and_attach_qr_code(wireguard_client, config_content)
    qr = RQRCode::QRCode.new(config_content)
    png = qr.as_png(size: 300)

    wireguard_client.qr_code.attach(
      io: StringIO.new(png.to_s),
      filename: "#{wireguard_client.name}.png",
      content_type: "image/png"
    )
  end

  # Remove peer from WireGuard (replaces pivpn -r)
  def remove_wireguard_peer(ssh, public_key)
    ssh.exec!("sudo wg set wg0 peer #{public_key} remove")
    Rails.logger.info "Removed peer with public key #{public_key[0..10]}..."
  end
end
