# app/jobs/expire_abandoned_subscriptions_job.rb
class ExpireAbandonedSubscriptionsJob < ApplicationJob
  queue_as :default

  # Maximum retries for SSH operations
  MAX_RETRIES = 3

  def perform
    # Find pending subscriptions older than 1 hour
    Subscription.where("status IN (?)", ['pending', 'payment_pending'])
                .where('created_at < ?', 1.hour.ago)
                .find_each do |subscription|
      process_subscription(subscription)
    end
  end

  private

  def process_subscription(subscription)
    Rails.logger.info "Processing abandoned subscription #{subscription.name} (ID: #{subscription.id})"

    begin
      # Expire the Stripe session if it exists
      if subscription.stripe_session_id.present?
        begin
          session = Stripe::Checkout::Session.retrieve(subscription.stripe_session_id)
          Stripe::Checkout::Session.expire(subscription.stripe_session_id) if session.status == 'open'
        rescue Stripe::InvalidRequestError
          Rails.logger.warn "Stripe session for subscription #{subscription.name} is already invalid"
        end
      end

      # Update subscription status
      subscription.update!(status: 'canceled')

      # Decrement server's current_subscriptions
      if subscription.server
        subscription.server.decrement!(:current_subscriptions)
        Rails.logger.info "Decremented server #{subscription.server.name} subscription count"
      end

      # Revoke WireGuard clients if they exist and server is available
      revoke_wireguard_clients(subscription) if subscription.server

      Rails.logger.info "Successfully processed abandoned subscription #{subscription.name}"
    rescue StandardError => e
      Rails.logger.error "Error processing abandoned subscription #{subscription.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Try to update the subscription status even if other operations fail
      subscription.update!(status: 'canceled') rescue nil
    end
  end

  def revoke_wireguard_clients(subscription)
    server = subscription.server
    private_key_path = "/tmp/server_#{server.id}_private_key_#{SecureRandom.hex(8)}"

    begin
      # Write the private key to the temporary file
      File.write(private_key_path, server.ssh_private_key)
      File.chmod(0600, private_key_path)

      # Revoke each WireGuard client
      subscription.wireguard_clients.each do |wireguard_client|
        revoke_client_with_retries(server, wireguard_client, private_key_path)
        wireguard_client.update!(status: "revoked")

        # Delete files from Wasabi
        delete_client_files_from_wasabi(wireguard_client)
      end
    ensure
      # Ensure the temporary file is deleted, even if an error occurs
      File.delete(private_key_path) if File.exist?(private_key_path)
    end
  end

  def revoke_client_with_retries(server, wireguard_client, private_key_path, retries = 0)
    return unless server.ssh_user.present?

    begin
      revoke_client_on_server(server, wireguard_client, private_key_path)
    rescue StandardError => e
      if retries < MAX_RETRIES
        sleep(2 ** retries) # Exponential backoff
        Rails.logger.info "Retrying (#{retries + 1}/#{MAX_RETRIES}) to revoke client #{wireguard_client.name}"
        retry
      else
        Rails.logger.error "Failed to revoke client #{wireguard_client.name} after #{MAX_RETRIES} attempts: #{e.message}"
      end
    end
  end

  def revoke_client_on_server(server, wireguard_client, private_key_path)
    ssh_user = server.ssh_user
    ip_address = server.ip_address

    Rails.logger.info "Attempting to revoke client #{wireguard_client.name} on server #{server.name} (#{ip_address})"

    Net::SSH.start(ip_address, ssh_user, keys: [private_key_path]) do |ssh|
      # Automatically answer "y" to the confirmation prompt
      output = ssh.exec!("LC_ALL=C echo 'y' | LC_ALL=C pivpn -r #{wireguard_client.name}")
      Rails.logger.info "Removed client #{wireguard_client.name}: #{output}"
    end
  rescue Net::SSH::AuthenticationFailed => e
    Rails.logger.error "SSH Authentication Failed for #{server.name}: #{e.message}"
    raise "Failed to authenticate with server #{server.name}. Please check the SSH credentials."
  rescue Net::SSH::ConnectionTimeout => e
    Rails.logger.error "SSH Connection Timeout for #{server.name}: #{e.message}"
    raise "Could not connect to server #{server.name}. The server may be down or unreachable."
  rescue Net::SSH::Exception => e
    Rails.logger.error "SSH Error for #{server.name}: #{e.message}"
    raise "SSH error occurred while connecting to #{server.name}: #{e.message}"
  rescue Errno::ECONNREFUSED => e
    Rails.logger.error "Connection refused to #{server.name} (#{ip_address}): #{e.message}"
    raise "Connection refused to server #{server.name}. Please check if the server is running and SSH is enabled."
  end

  def delete_client_files_from_wasabi(wireguard_client)
    # Delete config file from Wasabi
    if wireguard_client.config_file.attached?
      wireguard_client.config_file.purge
      Rails.logger.info "Deleted config file for #{wireguard_client.name} from Wasabi"
    else
      Rails.logger.warn "Config file not found for #{wireguard_client.name} in Wasabi"
    end

    # Delete QR code file from Wasabi
    if wireguard_client.qr_code.attached?
      wireguard_client.qr_code.purge
      Rails.logger.info "Deleted QR code file for #{wireguard_client.name} from Wasabi"
    else
      Rails.logger.warn "QR code file not found for #{wireguard_client.name} in Wasabi"
    end
  end
end
