class RevokeExpiredSubscriptionsJob < ApplicationJob
  queue_as :default
  # Maximum number of subscriptions to process in one job run
  BATCH_SIZE = 100
  # Maximum retries for SSH operations
  MAX_RETRIES = 3

  def perform
    start_time = Time.current
    Rails.logger.info "Starting RevokeExpiredSubscriptionsJob at #{start_time}"
    # Process subscriptions in batches
    process_batch
    duration = Time.current - start_time
    Rails.logger.info "Completed RevokeExpiredSubscriptionsJob in #{duration.round(2)} seconds"
  end

  private

  def process_batch
    # Find expired subscriptions in batches
    Subscription.where("expires_at < ? AND status = ?", Time.current, "active")
               .limit(BATCH_SIZE)
               .find_each do |subscription|
      process_subscription(subscription)
    end
  end

  def process_subscription(subscription)
    Rails.logger.info "Processing subscription #{subscription.name} (ID: #{subscription.id})"
    begin
      # Update subscription status first
      subscription.update!(status: "expired")
      # Get the server associated with this subscription
      server = subscription.server
      # Skip if no server is associated
      unless server
        Rails.logger.warn "Subscription #{subscription.name} has no associated server"
        return
      end
      # Generate a unique temporary file path for the private key
      private_key_path = "/tmp/server_#{server.id}_private_key_#{SecureRandom.hex(8)}"
      # Write the private key to the temporary file
      File.write(private_key_path, server.ssh_private_key)
      File.chmod(0600, private_key_path)
      # Update server's current_subscriptions count
      update_server_subscription_count(server, -1)
      # Revoke each WireGuard client
      subscription.wireguard_clients.each do |wireguard_client|
        revoke_client_with_retries(server, wireguard_client, private_key_path)
        wireguard_client.update!(status: "revoked")
      end
      # Delete files from Wasabi
      delete_client_files_from_wasabi(subscription)
      # Notify user
      notify_user(subscription)
      Rails.logger.info "Successfully processed subscription #{subscription.name}"
    rescue StandardError => e
      Rails.logger.error "Error processing subscription #{subscription.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Try to update the subscription status even if other operations fail
      subscription.update!(status: "expired") rescue nil
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

  def update_server_subscription_count(server, change)
    new_count = server.current_subscriptions + change
    new_count = [new_count, 0].max # Don't go below zero
    if new_count != server.current_subscriptions
      server.update!(current_subscriptions: new_count)
      Rails.logger.info "Updated server #{server.name} subscription count to #{new_count}"
    end
  rescue StandardError => e
    Rails.logger.error "Failed to update server #{server.name} subscription count: #{e.message}"
    # Continue even if server update fails
  end

  def delete_client_files_from_wasabi(subscription)
    subscription.wireguard_clients.each do |wireguard_client|
      sanitized_name = wireguard_client.name.gsub(/[@.]/, '_')

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

  def notify_user(subscription)
    # Send email notification
    SubscriptionMailer.subscription_expired(subscription).deliver_later
    # You could also add other notification methods here
    # (e.g., push notifications, SMS, etc.)
  rescue StandardError => e
    Rails.logger.error "Failed to send notification for subscription #{subscription.name}: #{e.message}"
  end
end
