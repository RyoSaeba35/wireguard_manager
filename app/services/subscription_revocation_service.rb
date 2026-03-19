# app/services/subscription_revocation_service.rb
class SubscriptionRevocationService
  include SingboxClientCreator
  include SshKeyManager

  MAX_RETRIES = 3

  def initialize(subscription)
    @subscription = subscription
    @server = subscription.server
  end

  def revoke!
    Rails.logger.info "Starting revocation for subscription #{@subscription.name}"

    unless @server
      Rails.logger.warn "Subscription #{@subscription.name} has no associated server — skipping SSH steps"
      return
    end

    private_key_path = nil

    begin
      private_key_path = write_private_key(@server)

      Net::SSH.start(@server.ip_address, @server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|
        revoke_wireguard_clients(ssh)
        revoke_singbox_clients(ssh)

        if @server.singbox_active? && singbox_clients_exist?
          validate_and_reload_singbox(ssh, @server)
        end
      end

      update_server_subscription_count
      delete_wireguard_files_from_wasabi

      Rails.logger.info "Successfully revoked subscription #{@subscription.name}"

    rescue Net::SSH::AuthenticationFailed => e
      Rails.logger.error "SSH auth failed for #{@server.name}: #{e.message}"
      raise
    rescue Net::SSH::ConnectionTimeout, Errno::ECONNREFUSED => e
      Rails.logger.error "SSH connection failed for #{@server.name}: #{e.message}"
      raise
    rescue Net::SSH::Exception => e
      Rails.logger.error "SSH error for #{@server.name}: #{e.message}"
      raise
    ensure
      File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
    end
  end

  private

  def revoke_wireguard_clients(ssh)
    @subscription.wireguard_clients.each do |client|
      revoke_wireguard_client_with_retries(ssh, client)
      client.update!(status: "revoked")
      Rails.logger.info "Revoked WireGuard client #{client.name}"
    end
  end

  def revoke_wireguard_client_with_retries(ssh, client, attempts = 0)
    output = ssh.exec!("LC_ALL=C echo 'y' | LC_ALL=C pivpn -r #{client.name}")
    Rails.logger.info "pivpn -r output for #{client.name}: #{output}"
  rescue => e
    attempts += 1
    if attempts < MAX_RETRIES
      sleep(2 ** attempts)
      Rails.logger.info "Retrying (#{attempts}/#{MAX_RETRIES}) revocation of #{client.name}"
      retry
    else
      Rails.logger.error "Failed to revoke #{client.name} after #{MAX_RETRIES} attempts: #{e.message}"
      raise
    end
  end

  def revoke_singbox_clients(ssh)
    return unless @server.singbox_active?
    return unless singbox_clients_exist?

    remove_singbox_clients(ssh, @subscription)

    @subscription.hysteria2_clients.update_all(status: "revoked")
    @subscription.shadowsocks_clients.update_all(status: "revoked")

    Rails.logger.info "Revoked sing-box clients for #{@subscription.name}"
  end

  def singbox_clients_exist?
    @subscription.hysteria2_clients.any? || @subscription.shadowsocks_clients.any?
  end

  def delete_wireguard_files_from_wasabi
    @subscription.wireguard_clients.each do |client|
      if client.config_file.attached?
        client.config_file.purge
        Rails.logger.info "Deleted config file for #{client.name}"
      else
        Rails.logger.warn "No config file found for #{client.name}"
      end

      if client.qr_code.attached?
        client.qr_code.purge
        Rails.logger.info "Deleted QR code for #{client.name}"
      else
        Rails.logger.warn "No QR code found for #{client.name}"
      end
    end
  end

  def update_server_subscription_count
    new_count = [@server.current_subscriptions - 1, 0].max
    @server.update!(current_subscriptions: new_count)
    Rails.logger.info "Updated #{@server.name} subscription count to #{new_count}"
  rescue => e
    Rails.logger.error "Failed to update subscription count for #{@server.name}: #{e.message}"
  end
end
