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

    # Create the subscription
    subscription = @user.subscriptions.create!(@subscription_params.merge(
      name: @subscription_name,
      expires_at: 5.minutes.from_now,
      status: "active"
    ))

    # Create 3 WireGuard clients
    3.times do |i|
      client_number = i + 1
      client_name = "#{@subscription_name}_#{client_number}"

      # Create the WireGuard client on the Raspberry Pi
      create_client_on_pi(client_name)

      # Fetch the client details from the Raspberry Pi
      private_key, public_key, ip_address = fetch_client_details(client_name)

      # Validate IP address
      unless ip_address && ip_address.match?(/\A(\d{1,3}\.){3}\d{1,3}\z/)
        Rails.logger.error "Invalid IP address for #{client_name}: #{ip_address.inspect}"
        raise "Failed to fetch a valid IP address for #{client_name}"
      end

      # Create the WireguardClient record in the database
      wireguard_client = subscription.wireguard_clients.create!(
        name: client_name,
        private_key: private_key,
        public_key: public_key,
        ip_address: ip_address,
        expires_at: subscription.expires_at,
        status: "active"
      )

      # Download the config file from the Raspberry Pi
      download_config_file(wireguard_client)

      # Generate and download the QR code
      generate_qr_code(wireguard_client)
    end
    subscription
  rescue StandardError => e
    Rails.logger.error "Error creating subscription and WireGuard clients: #{e.message}"
    raise e
  end

  private

  def create_client_on_pi(client_name)
    Rails.logger.info "Creating client #{client_name} on Raspberry Pi..."
    Net::SSH.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |ssh|
      output = ssh.exec!("LC_ALL=C echo '#{client_name}' | LC_ALL=C pivpn -a")
      Rails.logger.info "pivpn -a output for #{client_name}: #{output}"
      ssh.exec!("sudo cp /etc/wireguard/configs/#{client_name}.conf /home/pi/configs/")
      ssh.exec!("sudo chown pi:pi /home/pi/configs/#{client_name}.conf")
      ssh.exec!("chmod 644 /home/pi/configs/#{client_name}.conf")
    end
  end

  def fetch_client_details(client_name)
    Net::SSH.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |ssh|
      # Fetch the private key
      private_key_cmd = "LC_ALL=C cat /home/pi/configs/#{client_name}.conf | LC_ALL=C grep 'PrivateKey'"
      private_key_output = ssh.exec!(private_key_cmd)
      private_key = private_key_output.chomp.split(' = ').last.strip

      # Fetch the public key from the client config file
      public_key_cmd = "LC_ALL=C cat /home/pi/configs/#{client_name}.conf | LC_ALL=C grep -A 5 '[Peer]' | LC_ALL=C grep 'PublicKey' | head -n 1"
      public_key_output = ssh.exec!(public_key_cmd)
      public_key = public_key_output.chomp.split(' = ').last.strip

      # Fetch the IP address from the client config file
      ip_address_cmd = "LC_ALL=C cat /home/pi/configs/#{client_name}.conf | LC_ALL=C grep 'Address' | LC_ALL=C cut -d'=' -f2 | LC_ALL=C cut -d',' -f1 | LC_ALL=C tr -d ' '"
      ip_address_output = ssh.exec!(ip_address_cmd)
      ip_address = ip_address_output.chomp.split('/').first.strip

      Rails.logger.info "Private Key: #{private_key}, Public Key: #{public_key}, IP Address: #{ip_address}"
      [private_key, public_key, ip_address]
    end
  end

  def download_config_file(wireguard_client)
    config_dir = Rails.root.join('public', 'configs')
    Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
    sanitized_name = wireguard_client.name.gsub(/[@.]/, '_')
    remote_path = "/home/pi/configs/#{wireguard_client.name}.conf"
    local_path = config_dir.join("#{sanitized_name}.conf")

    begin
      Net::SCP.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |scp|
        scp.download!(remote_path, local_path)
      end
    rescue Net::SCP::Error => e
      Rails.logger.error "SCP Error downloading config file for #{wireguard_client.name}: #{e.message}"
      raise "Failed to download config file for #{wireguard_client.name}: #{e.message}"
    end
  end

  def generate_qr_code(wireguard_client)
    qr_dir = Rails.root.join('public', 'qr_codes')
    Dir.mkdir(qr_dir) unless Dir.exist?(qr_dir)
    qr_file_path = qr_dir.join("#{wireguard_client.name}.png")

    begin
      Net::SSH.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |ssh|
        qr_generation_output = ssh.exec!("qrencode -t PNG -o /home/pi/configs/#{wireguard_client.name}.png < /home/pi/configs/#{wireguard_client.name}.conf")
        Rails.logger.info "QR generation output for #{wireguard_client.name}: #{qr_generation_output}"
        qr_exists_cmd = "ls /home/pi/configs/#{wireguard_client.name}.png 2>&1"
        qr_exists_output = ssh.exec!(qr_exists_cmd)
        Rails.logger.info "QR file existence check for #{wireguard_client.name}: #{qr_exists_output}"
      end

      Net::SFTP.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |sftp|
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
end
