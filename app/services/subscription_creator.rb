# app/services/subscription_creator.rb
require 'net/ssh'
require 'net/scp'
require 'net/sftp'

class SubscriptionCreator
  def initialize(user, subscription_name, subscription_params)
    @user = user
    @subscription_name = subscription_name
    @subscription_params = subscription_params
  end

  def call
    Rails.logger.info "Creating subscription: #{@subscription_name}"

    selected_plan = Plan.find(@subscription_params[:plan_id])
    server = select_server

    if server.nil?
      raise "No available servers"
    end

    expires_at = calculate_expires_at(selected_plan)
    subscription = create_subscription(server, expires_at)

    # Create 3 WireGuard clients
    3.times do |i|
      client_number = i + 1
      client_name = "#{@subscription_name}_#{client_number}"

      # Create the WireGuard client on the server
      create_client_on_server(server, client_name, subscription)
    end

    subscription
  rescue StandardError => e
    Rails.logger.error "Error creating subscription and WireGuard clients: #{e.message}"
    raise e
  end

  private

  def select_server
    Server.where(active: true)
          .where("current_subscriptions < max_subscriptions")
          .order(:current_subscriptions)
          .first
  end

  def calculate_expires_at(selected_plan)
    case selected_plan.interval
    when 'week'  then 1.week.from_now
    when 'month' then 1.month.from_now
    when 'year'  then 1.year.from_now
    else 1.month.from_now
    end
  end

  def create_subscription(server, expires_at)
    @user.subscriptions.create!(
      @subscription_params.merge(
        name: @subscription_name,
        expires_at: expires_at,
        status: "active",
        server: server
      )
    ).tap do |subscription|
      server.increment!(:current_subscriptions)
    end
  end

  def create_client_on_server(server, client_name, subscription)
    Rails.logger.info "Creating client #{client_name} on #{server.name}..."

    # Use Net::SSH to connect to the server
    Net::SSH.start(server.ip_address, server.ssh_user, password: server.ssh_password) do |ssh|
      # Create the client
      output = ssh.exec!("LC_ALL=C echo '#{client_name}' | LC_ALL=C pivpn -a")
      Rails.logger.info "pivpn -a output for #{client_name}: #{output}"

      # Copy the config file
      ssh.exec!("sudo cp /etc/wireguard/configs/#{client_name}.conf /home/pi/configs/")
      ssh.exec!("sudo chown pi:pi /home/pi/configs/#{client_name}.conf")
      ssh.exec!("chmod 644 /home/pi/configs/#{client_name}.conf")

      # Fetch client details
      private_key, public_key, ip_address = fetch_client_details(ssh, client_name)

      # Validate IP address
      unless ip_address && ip_address.match?(/\A(\d{1,3}\.){3}\d{1,3}\z/)
        Rails.logger.error "Invalid IP address for #{client_name}: #{ip_address.inspect}"
        raise "Failed to fetch a valid IP address for #{client_name}"
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
      download_config_file(ssh, wireguard_client, server)

      # Generate and download the QR code
      generate_qr_code(ssh, wireguard_client, server)
    end
  end

  def fetch_client_details(ssh, client_name)
    # Fetch the private key
    private_key_cmd = "LC_ALL=C cat /home/pi/configs/#{client_name}.conf | LC_ALL=C grep 'PrivateKey'"
    private_key_output = ssh.exec!(private_key_cmd)
    private_key = private_key_output.chomp.split(' = ').last.strip

    # Fetch the public key
    public_key_cmd = "LC_ALL=C cat /home/pi/configs/#{client_name}.conf | LC_ALL=C grep -A 5 '[Peer]' | LC_ALL=C grep 'PublicKey' | head -n 1"
    public_key_output = ssh.exec!(public_key_cmd)
    public_key = public_key_output.chomp.split(' = ').last.strip

    # Fetch the IP address
    ip_address_cmd = "LC_ALL=C cat /home/pi/configs/#{client_name}.conf | LC_ALL=C grep 'Address' | LC_ALL=C cut -d'=' -f2 | LC_ALL=C cut -d',' -f1 | LC_ALL=C tr -d ' '"
    ip_address_output = ssh.exec!(ip_address_cmd)
    ip_address = ip_address_output.chomp.split('/').first.strip

    Rails.logger.info "Private Key: #{private_key}, Public Key: #{public_key}, IP Address: #{ip_address}"
    [private_key, public_key, ip_address]
  end

  def download_config_file(ssh, wireguard_client, server)
    config_dir = Rails.root.join('public', 'configs')
    Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
    sanitized_name = wireguard_client.name.gsub(/[@.]/, '_')
    remote_path = "/home/pi/configs/#{wireguard_client.name}.conf"
    local_path = config_dir.join("#{sanitized_name}.conf")

    Net::SCP.start(server.ip_address, server.ssh_user, password: server.ssh_password) do |scp|
      scp.download!(remote_path, local_path)
    end
  rescue Net::SCP::Error => e
    Rails.logger.error "SCP Error downloading config file for #{wireguard_client.name}: #{e.message}"
    raise "Failed to download config file for #{wireguard_client.name}: #{e.message}"
  end

  def generate_qr_code(ssh, wireguard_client, server)
    qr_dir = Rails.root.join('public', 'qr_codes')
    Dir.mkdir(qr_dir) unless Dir.exist?(qr_dir)
    qr_file_path = qr_dir.join("#{wireguard_client.name}.png")

    # Generate QR code on the server
    ssh.exec!("qrencode -t PNG -o /home/pi/configs/#{wireguard_client.name}.png < /home/pi/configs/#{wireguard_client.name}.conf")

    # Download the QR code
    Net::SFTP.start(server.ip_address, server.ssh_user, password: server.ssh_password) do |sftp|
      File.open(qr_file_path, 'wb') do |file|
        sftp.download!("/home/pi/configs/#{wireguard_client.name}.png", file)
      end
    end
  rescue Encoding::UndefinedConversionError => e
    Rails.logger.error "Encoding error generating or downloading QR code for #{wireguard_client.name}: #{e.message}"
    raise "Failed to generate or download QR code for #{wireguard_client.name} due to encoding error: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Error generating or downloading QR code for #{wireguard_client.name}: #{e.message}"
    raise "Failed to generate or download QR code for #{wireguard_client.name}: #{e.message}"
  end
end
