# app/jobs/preallocate_subscriptions_job.rb
class PreallocateSubscriptionsJob < ApplicationJob
  queue_as :default

  # Number of pre-allocated subscriptions to maintain per server
  TARGET_POOL_SIZE = 20

  def perform(server_id = nil)
    if server_id
      # Pre-allocate for a specific server
      servers = [Server.find(server_id)]
    else
      # Pre-allocate for all active servers with available capacity
      servers = Server.where(active: true)
                     .where("current_subscriptions < max_subscriptions")
    end

    servers.each do |server|
      current_preallocated = server.subscriptions.preallocated.count
      next if current_preallocated >= TARGET_POOL_SIZE

      Rails.logger.info "Pre-allocating subscriptions for server #{server.name} (ID: #{server.id})"

      (current_preallocated...TARGET_POOL_SIZE).each do |i|
        begin
          # Generate a unique subscription name
          subscription_name = loop do
            random_name = SecureRandom.alphanumeric(6).upcase
            break random_name unless server.subscriptions.exists?(name: random_name)
          end

          # Use the first active plan as default (or pass plan_id as argument)
          default_plan = Plan.where(active: true).first
          next unless default_plan

          # Create a pre-allocated subscription
          subscription = server.subscriptions.create!(
            name: subscription_name,
            status: "preallocated",
            plan_id: default_plan.id,
            price: default_plan.price,
            expires_at: 1.month.from_now, # Placeholder, will be updated when assigned to user
            user_id: nil
          )

          Rails.logger.info "Created pre-allocated subscription: #{subscription_name}"

          # Create 3 WireGuard clients for this subscription
          3.times do |client_number|
            client_name = "#{subscription_name}_#{client_number + 1}"

            # Generate a unique temporary file path for the private key
            private_key_path = "/tmp/server_#{server.id}_private_key_#{SecureRandom.hex(8)}"
            File.write(private_key_path, server.ssh_private_key)
            File.chmod(0600, private_key_path)

            # Create client on server via SSH
            Net::SSH.start(server.ip_address, server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|
              output = ssh.exec!("echo '#{client_name}' | pivpn -a")
              Rails.logger.info "Created WireGuard client #{client_name}: #{output}"

              # Fetch client details
              private_key, public_key, ip_address = fetch_client_details(ssh, client_name)

              # Create WireguardClient record
              subscription.wireguard_clients.create!(
                name: client_name,
                private_key: private_key,
                public_key: public_key,
                ip_address: ip_address,
                status: "active",
                expires_at: subscription.expires_at
              )

              # Copy the config file to a temporary location
              ssh.exec!("sudo cp /etc/wireguard/configs/#{client_name}.conf /home/pi/configs/")
              ssh.exec!("sudo chown pi:pi /home/pi/configs/#{client_name}.conf")
              ssh.exec!("chmod 644 /home/pi/configs/#{client_name}.conf")

              # Generate and upload config file
              config_file_path = "/home/pi/configs/#{client_name}.conf"
              temp_file = Tempfile.new(["#{client_name}", '.conf'])
              Net::SCP.start(server.ip_address, server.ssh_user, keys: [private_key_path]) do |scp|
                scp.download!(config_file_path, temp_file.path)
              end

              # Attach config file to the client
              subscription.wireguard_clients.last.config_file.attach(
                io: File.open(temp_file.path),
                filename: "#{client_name}.conf",
                content_type: 'application/octet-stream'
              )
              temp_file.close
              temp_file.unlink

              # Generate and upload QR code
              ssh.exec!("qrencode -t PNG -o /home/pi/configs/#{client_name}.png < /home/pi/configs/#{client_name}.conf")
              qr_code_path = "/home/pi/configs/#{client_name}.png"
              qr_temp_file = Tempfile.new(["#{client_name}", '.png'])
              Net::SFTP.start(server.ip_address, server.ssh_user, keys: [private_key_path]) do |sftp|
                sftp.download!(qr_code_path, qr_temp_file.path)
              end

              # Attach QR code to the client
              subscription.wireguard_clients.last.qr_code.attach(
                io: File.open(qr_temp_file.path),
                filename: "#{client_name}.png",
                content_type: 'image/png'
              )
              qr_temp_file.close
              qr_temp_file.unlink
            end
          rescue Net::SSH::Exception => e
            Rails.logger.error "SSH Error creating client #{client_name}: #{e.message}"
            subscription.destroy! # Clean up if client creation fails
            next
          ensure
            File.delete(private_key_path) if File.exist?(private_key_path)
          end
        rescue => e
          Rails.logger.error "Error pre-allocating subscription #{subscription_name}: #{e.message}"
          next
        end
      end
    end
  end

  private

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

    [private_key, public_key, ip_address]
  end
end
