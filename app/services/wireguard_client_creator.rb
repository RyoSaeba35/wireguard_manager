# app/services/wireguard_client_creator.rb
module WireguardClientCreator
  def create_client_on_server(ssh, client_name, subscription, server, private_key_path)
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
    ssh.exec!("sudo cp /etc/wireguard/configs/#{client_name}.conf /home/pi/configs/")
    ssh.exec!("sudo chown pi:pi /home/pi/configs/#{client_name}.conf")
    ssh.exec!("chmod 644 /home/pi/configs/#{client_name}.conf")
    # Fetch client details
    private_key, public_key, ip_address = fetch_client_details(ssh, client_name)
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
    # Download the config file
    download_config_file(ssh, wireguard_client, server, private_key_path)
    # Generate and download the QR code
    generate_qr_code(ssh, wireguard_client, server, private_key_path)
  end

  def fetch_client_details(ssh, client_name)
    # Fetch the private key
    private_key_cmd = "cat /home/pi/configs/#{client_name}.conf | grep 'PrivateKey'"
    private_key_output = ssh.exec!(private_key_cmd)
    private_key = private_key_output.chomp.split(' = ').last.strip
    # Fetch the public key
    public_key_cmd = "cat /home/pi/configs/#{client_name}.conf | grep -A 5 '[Peer]' | grep 'PublicKey' | head -n 1"
    public_key_output = ssh.exec!(public_key_cmd)
    public_key = public_key_output.chomp.split(' = ').last.strip
    # Fetch the IP address
    ip_address_cmd = "cat /home/pi/configs/#{client_name}.conf | grep 'Address' | cut -d'=' -f2 | cut -d',' -f1 | cut -d'/' -f1 | tr -d ' '"
    ip_address_output = ssh.exec!(ip_address_cmd)
    ip_address = ip_address_output.chomp.strip
    Rails.logger.info "Private Key: #{private_key}, Public Key: #{public_key}, IP Address: #{ip_address}"
    [private_key, public_key, ip_address]
  end

  def download_config_file(ssh, wireguard_client, server, private_key_path)
    config_dir = Rails.root.join('storage', 'configs')
    Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
    sanitized_name = wireguard_client.name.gsub(/[@.]/, '_')
    remote_path = "/home/pi/configs/#{wireguard_client.name}.conf"
    local_path = config_dir.join("#{sanitized_name}.conf")
    Rails.logger.info "Downloading config file from #{remote_path} to #{local_path}"
    Net::SCP.start(server.ip_address, server.ssh_user, keys: [private_key_path]) do |scp|
      scp.download!(remote_path, local_path)
      Rails.logger.info "Successfully downloaded config file for #{wireguard_client.name}"
    end
  end

  def generate_qr_code(ssh, wireguard_client, server, private_key_path)
    qr_dir = Rails.root.join('storage', 'qr_codes')
    Dir.mkdir(qr_dir) unless Dir.exist?(qr_dir)
    qr_file_path = qr_dir.join("#{wireguard_client.name}.png")
    Rails.logger.info "Generating QR code for #{wireguard_client.name}"
    ssh.exec!("qrencode -t PNG -o /home/pi/configs/#{wireguard_client.name}.png < /home/pi/configs/#{wireguard_client.name}.conf")
    Net::SFTP.start(server.ip_address, server.ssh_user, keys: [private_key_path]) do |sftp|
      File.open(qr_file_path, 'wb') do |file|
        sftp.download!("/home/pi/configs/#{wireguard_client.name}.png", file)
        Rails.logger.info "Successfully downloaded QR code for #{wireguard_client.name}"
      end
    end
  end
end
