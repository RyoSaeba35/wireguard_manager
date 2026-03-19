# app/jobs/wireguard_client_creation_job.rb
class WireguardClientCreationJob < ApplicationJob
  include WireguardClientCreator
  include SingboxClientCreator
  queue_as :default

  def perform(subscription_id)
    subscription = Subscription.find(subscription_id)
    server = subscription.server

    Rails.logger.info "Creating VPN clients for subscription #{subscription.name}"

    private_key_path = nil
    wg_clients_created = 0

    private_key_path = write_private_key(server)

    Net::SSH.start(server.ip_address, server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|

      CLIENTS_PER_SUBSCRIPTION.times do |i|
        client_name = "#{subscription.name}_#{i + 1}"

        if subscription.wireguard_clients.exists?(name: client_name)
          Rails.logger.info "Skipping existing WireGuard client: #{client_name}"
          wg_clients_created += 1
          next
        end

        result = create_client_on_server(ssh, client_name, subscription, server)
        wg_clients_created += 1 if result
      rescue => e
        Rails.logger.error "Error creating WireGuard client #{client_name}: #{e.message}"
      end

      # Non-fatal — WireGuard clients still valid if sing-box fails
      if server.singbox_active? && subscription.hysteria2_clients.empty?
        begin
          create_singbox_clients(ssh, subscription, server)
          validate_and_reload_singbox(ssh, server)
        rescue => e
          Rails.logger.error "Sing-box setup failed for #{subscription.name}: #{e.message}"
        end
      end
    end

    if wg_clients_created == CLIENTS_PER_SUBSCRIPTION
      subscription.update!(status: "active")
      UserMailer.vpn_config_ready(subscription.user, subscription).deliver_later
      Rails.logger.info "All clients created successfully for #{subscription.name}"
    else
      subscription.update!(status: "failed")
      raise "Expected #{CLIENTS_PER_SUBSCRIPTION} WireGuard clients, created #{wg_clients_created}"
    end

  rescue Net::SSH::Exception => e
    Rails.logger.error "SSH connection failed for subscription #{subscription_id}: #{e.message}"
    subscription&.update!(status: "failed")
    raise
  ensure
    File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
  end
end
