# app/jobs/wireguard_client_creation_job.rb
class WireguardClientCreationJob < ApplicationJob
  include WireguardClientCreator
  queue_as :default

  def perform(subscription_id)
    subscription = Subscription.find(subscription_id)
    server = subscription.server
    Rails.logger.info "Creating WireGuard clients for subscription: #{subscription.name}"

    # Generate a unique temporary file path for the private key
    private_key_path = "/tmp/server_#{server.id}_private_key_#{SecureRandom.hex(8)}"
    # Write the private key to the temporary file
    File.write(private_key_path, server.ssh_private_key)
    File.chmod(0600, private_key_path)

    clients_created = 0
    total_clients_to_create = 3

    total_clients_to_create.times do |i|
      client_number = i + 1
      client_name = "#{subscription.name}_#{client_number}"

      if subscription.wireguard_clients.exists?(name: client_name)
        Rails.logger.info "Skipping existing client: #{client_name}"
        clients_created += 1
        next
      end

      begin
        Net::SSH.start(server.ip_address, server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|
          create_client_on_server(ssh, client_name, subscription, server, private_key_path)
          clients_created += 1
        end
      rescue Net::SSH::Exception => e
        Rails.logger.error "SSH Error for client #{client_name}: #{e.message}"
        next
      end
    end

    if clients_created == total_clients_to_create
      subscription.update!(status: "active")
      UserMailer.vpn_config_ready(subscription.user, subscription).deliver_later
      Rails.logger.info "All #{total_clients_to_create} WireGuard clients were created successfully"
    else
      Rails.logger.error "No WireGuard clients were created for subscription #{subscription_id}"
      subscription.update!(status: "failed")
      raise "No WireGuard clients were created"
    end
  ensure
    # Ensure the temporary file is deleted, even if an error occurs
    File.delete(private_key_path) if File.exist?(private_key_path)
  end
end
