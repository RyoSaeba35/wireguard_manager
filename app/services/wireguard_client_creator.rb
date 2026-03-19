require 'tempfile'

module WireguardClientCreator
  include SshKeyManager

  def create_client_on_server(ssh, client_name, subscription, server)
    Rails.logger.info "Creating client #{client_name} on #{server.name}..."

    # Skip if client already exists
    if subscription.wireguard_clients.exists?(name: client_name)
      Rails.logger.info "Skipping existing client: #{client_name}"
      return
    end

    # Create the client
    output = ssh.exec!("echo '#{client_name}' | pivpn -a")
    Rails.logger.info "pivpn -a output for #{client_name}: #{output}"

    # Copy the config file
    ssh.exec!("sudo cp /etc/wireguard/configs/#{client_name}.conf /home/#{server.ssh_user}/configs/")
    ssh.exec!("sudo chown #{server.ssh_user}:#{server.ssh_user} /home/#{server.ssh_user}/configs/#{client_name}.conf")
    ssh.exec!("chmod 644 /home/#{server.ssh_user}/configs/#{client_name}.conf")

    # Fetch client details
    private_key, public_key, ip_address = fetch_client_details(ssh, client_name, server)

    unless ip_address && ip_address.match?(/\A(\d{1,3}\.){3}\d{1,3}\z/)
      Rails.logger.error "Invalid IP address for #{client_name}: #{ip_address.inspect}"
      raise "Failed to fetch a valid IP address for #{client_name}"
    end

    # Check if there's an existing active client with the same IP address
    existing_client = WireguardClient.where(ip_address: ip_address, status: "active").first
    if existing_client
      Rails.logger.warn "IP address #{ip_address} is already taken by client #{existing_client.name}. Skipping creation of #{client_name}."
      return
    end

    # Create the WireguardClient record
    wireguard_client = subscription.wireguard_clients.create!(
      name: client_name,
      private_key: private_key,
      public_key: public_key,
      ip_address: ip_address,
      expires_at: subscription.expires_at,
      status: "active"
    )

    # Download, attach config file and capture content for QR code
    config_content = download_and_attach_config_file(ssh, wireguard_client, server)

    # Generate and attach QR code from config content
    generate_and_attach_qr_code(wireguard_client, config_content)
  end

  def fetch_client_details(ssh, client_name, server)
    private_key = ssh.exec!("cat /home/#{server.ssh_user}/configs/#{client_name}.conf | grep 'PrivateKey'").chomp.split(' = ').last.strip
    public_key = ssh.exec!("cat /home/#{server.ssh_user}/configs/#{client_name}.conf | grep -A 5 '[Peer]' | grep 'PublicKey' | head -n 1").chomp.split(' = ').last.strip
    ip_address = ssh.exec!("cat /home/#{server.ssh_user}/configs/#{client_name}.conf | grep 'Address' | cut -d'=' -f2 | cut -d',' -f1 | cut -d'/' -f1 | tr -d ' '").chomp.strip

    Rails.logger.info "Fetched details for #{client_name} — IP: #{ip_address}, pubkey: #{public_key}"

    [private_key, public_key, ip_address]
  end

  def download_and_attach_config_file(ssh, wireguard_client, server)
    remote_path = "/home/#{server.ssh_user}/configs/#{wireguard_client.name}.conf"

    Tempfile.create(["#{wireguard_client.name}", '.conf']) do |temp_file|
      ssh.scp.download!(remote_path, temp_file.path)
      config_content = File.read(temp_file.path)

      wireguard_client.config_file.attach(
        io: StringIO.new(config_content),
        filename: "#{wireguard_client.name}.conf",
        content_type: 'application/octet-stream'
      )

      config_content # return for QR code generation
    end
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
end
