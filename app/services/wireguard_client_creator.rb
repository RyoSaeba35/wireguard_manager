require 'net/ssh'
require 'net/scp'
require 'net/sftp'

class WireguardClientCreator
  def initialize(user, client_name)
    @user = user
    @client_name = client_name
  end

  def call
    Rails.logger.info "Creating WireGuard client: #{@client_name}"

    # Use pivpn -a to create the client on the Raspberry Pi
    create_client_on_pi

    # Fetch the client details from the Raspberry Pi
    private_key, public_key, ip_address = fetch_client_details

    # Validate IP address
    unless ip_address && ip_address.match?(/\A(\d{1,3}\.){3}\d{1,3}\z/)
      Rails.logger.error "Invalid IP address: #{ip_address.inspect}"
      raise "Failed to fetch a valid IP address"
    end

    # # Create the WireguardClient record in the database
    # wireguard_client = @user.wireguard_clients.create!(
    #   name: @client_name,
    #   private_key: private_key,
    #   public_key: public_key,
    #   ip_address: ip_address,
    #   expires_at: 1.month.from_now,
    #   status: "active"
    # )

    # Create the WireguardClient record in the database
    wireguard_client = @user.wireguard_clients.create!(
      name: @client_name,
      private_key: private_key,
      public_key: public_key,
      ip_address: ip_address,
      expires_at: 5.minute.from_now,
      status: "active"
    )

    # Create the Subscription record
    @user.subscriptions.create!(
      wireguard_client: wireguard_client,
      expires_at: wireguard_client.expires_at,
      status: "active"
    )

    # Download the config file from the Raspberry Pi
    download_config_file(wireguard_client)

    # Generate and download the QR code
    generate_qr_code(wireguard_client)

    wireguard_client
  rescue StandardError => e
    Rails.logger.error "Error creating WireGuard client: #{e.message}"
    raise e
  end

  private

  def create_client_on_pi
    Rails.logger.info "Creating client on Raspberry Pi..."
    Net::SSH.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |ssh|
      output = ssh.exec!("LC_ALL=C echo '#{@client_name}' | LC_ALL=C pivpn -a")
      Rails.logger.info "pivpn -a output: #{output}"
      ssh.exec!("sudo cp /etc/wireguard/configs/#{@client_name}.conf /home/pi/configs/")
      ssh.exec!("sudo chown pi:pi /home/pi/configs/#{@client_name}.conf")
      ssh.exec!("chmod 644 /home/pi/configs/#{@client_name}.conf")
    end
  end


  def fetch_client_details
    Net::SSH.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |ssh|
      # Fetch the private key
      private_key_cmd = "LC_ALL=C cat /home/pi/configs/#{@client_name}.conf | LC_ALL=C grep 'PrivateKey'"
      private_key_output = ssh.exec!(private_key_cmd)
      private_key = private_key_output.chomp.split(' = ').last.strip

      # Fetch the public key from the client config file
      public_key_cmd = "LC_ALL=C cat /home/pi/configs/#{@client_name}.conf | LC_ALL=C grep -A 5 '[Peer]' | LC_ALL=C grep 'PublicKey' | head -n 1"
      public_key_output = ssh.exec!(public_key_cmd)
      public_key = public_key_output.chomp.split(' = ').last.strip

      # Fetch the IP address from the client config file
      ip_address_cmd = "LC_ALL=C cat /home/pi/configs/#{@client_name}.conf | LC_ALL=C grep 'Address' | LC_ALL=C cut -d'=' -f2 | LC_ALL=C cut -d',' -f1 | LC_ALL=C tr -d ' '"
      ip_address_output = ssh.exec!(ip_address_cmd)
      ip_address = ip_address_output.chomp.split('/').first.strip

      Rails.logger.info "Private Key: #{private_key}, Public Key: #{public_key}, IP Address: #{ip_address}"

      [private_key, public_key, ip_address]
    end
  end

  # def download_config_file(wireguard_client)
  #   config_dir = Rails.root.join('public', 'configs')
  #   Dir.mkdir(config_dir) unless Dir.exist?(config_dir)

  #   begin
  #     Net::SCP.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |scp|
  #       scp.download!("/home/pi/configs/#{wireguard_client.name}.conf", config_dir.join("#{wireguard_client.name}.conf"))
  #     end
  #   rescue Net::SCP::Error => e
  #     Rails.logger.error "SCP Error downloading config file: #{e.message}"
  #     raise "Failed to download config file: #{e.message}"
  #   end
  # end

  def download_config_file(wireguard_client)
    config_dir = Rails.root.join('public', 'configs')
    Dir.mkdir(config_dir) unless Dir.exist?(config_dir)

    # Sanitize the filename by replacing @ and . with underscores
    sanitized_name = wireguard_client.name.gsub(/[@.]/, '_')

    # Define remote and local paths
    remote_path = "/home/pi/configs/#{wireguard_client.name}.conf"
    local_path = config_dir.join("#{sanitized_name}.conf")

    begin
      Net::SCP.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |scp|
        scp.download!(remote_path, local_path)
      end
    rescue Net::SCP::Error => e
      Rails.logger.error "SCP Error downloading config file: #{e.message}"
      raise "Failed to download config file: #{e.message}"
    end
  end

  def generate_qr_code(wireguard_client)
    qr_dir = Rails.root.join('public', 'qr_codes')
    Dir.mkdir(qr_dir) unless Dir.exist?(qr_dir)

    qr_file_path = qr_dir.join("#{wireguard_client.name}.png")

    begin
      Net::SSH.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |ssh|
        # Generate the QR code using qrencode
        qr_generation_output = ssh.exec!("qrencode -t PNG -o /home/pi/configs/#{wireguard_client.name}.png < /home/pi/configs/#{wireguard_client.name}.conf")
        Rails.logger.info "QR generation output: #{qr_generation_output}"

        # Check if the QR code file exists
        qr_exists_cmd = "ls /home/pi/configs/#{wireguard_client.name}.png 2>&1"
        qr_exists_output = ssh.exec!(qr_exists_cmd)
        Rails.logger.info "QR file existence check: #{qr_exists_output}"
      end

      # Use SFTP to download the QR code
      Net::SFTP.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |sftp|
        File.open(qr_file_path, 'wb') do |file|
          sftp.download!("/home/pi/configs/#{wireguard_client.name}.png", file)
        end
      end
    rescue Encoding::UndefinedConversionError => e
      Rails.logger.error "Encoding error generating or downloading QR code: #{e.message}"
      raise "Failed to generate or download QR code due to encoding error: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "Error generating or downloading QR code: #{e.message}"
      raise "Failed to generate or download QR code: #{e.message}"
    end
  end
end
