# app/jobs/wireguard_client_creation_job.rb
class WireguardClientCreationJob < ApplicationJob
  include WireguardClientCreator
  queue_as :default

  def perform(subscription_id)
    subscription = Subscription.find(subscription_id)
    server = subscription.server

    Rails.logger.info "Creating WireGuard clients for subscription: #{subscription.name}"

    clients_created = 0

    3.times do |i|
      client_number = i + 1
      client_name = "#{subscription.name}_#{client_number}"

      # Skip if client already exists in the database
      if subscription.wireguard_clients.exists?(name: client_name)
        Rails.logger.info "Skipping existing client: #{client_name}"
        clients_created += 1
        next
      end

      begin
        Net::SSH.start(server.ip_address, server.ssh_user, password: server.ssh_password) do |ssh|
          create_client_on_server(ssh, client_name, subscription, server)
          clients_created += 1
        end
      rescue Net::SSH::Exception => e
        Rails.logger.error "SSH Error for client #{client_name}: #{e.message}"
        next
      end
    end

    if clients_created >= 1
      subscription.update!(status: "active")
      UserMailer.vpn_config_ready(subscription.user, subscription).deliver_later
    else
      Rails.logger.error "No WireGuard clients were created for subscription #{subscription_id}"
      subscription.update!(status: "failed")
      raise "No WireGuard clients were created"
    end
  end
end
