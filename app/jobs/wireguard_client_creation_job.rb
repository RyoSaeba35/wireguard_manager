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

      # ⭐ NEW: Batch create all WireGuard clients at once
      client_names = CLIENTS_PER_SUBSCRIPTION.times.map do |i|
        "#{subscription.name}_#{i + 1}"
      end

      # Filter out existing clients
      existing_names = subscription.wireguard_clients.pluck(:name)
      new_client_names = client_names - existing_names

      if new_client_names.any?
        wg_clients_created = create_clients_batch(ssh, new_client_names, subscription, server)
        Rails.logger.info "Created #{wg_clients_created} new WireGuard clients"
      else
        Rails.logger.info "All WireGuard clients already exist"
        wg_clients_created = CLIENTS_PER_SUBSCRIPTION
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

    if subscription.wireguard_clients.count >= CLIENTS_PER_SUBSCRIPTION
      subscription.update!(status: "active")
      UserMailer.vpn_config_ready(subscription.user, subscription).deliver_later
      Rails.logger.info "All clients created successfully for #{subscription.name}"
    else
      subscription.update!(status: "failed")
      raise "Expected #{CLIENTS_PER_SUBSCRIPTION} WireGuard clients, have #{subscription.wireguard_clients.count}"
    end

  rescue Net::SSH::Exception => e
    Rails.logger.error "SSH connection failed for subscription #{subscription_id}: #{e.message}"
    subscription&.update!(status: "failed")
    raise
  ensure
    File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
  end
end
