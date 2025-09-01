class RevokeExpiredSubscriptionsJob < ApplicationJob
  queue_as :default
  require 'net/ssh'

  def perform
    Subscription.where("expires_at < ? AND status = ?", Time.current, "active").each do |subscription|
      subscription.wireguard_clients.each do |wireguard_client|
        begin
          Net::SSH.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |ssh|
            # Automatically answer "y" to the confirmation prompt
            output = ssh.exec!("LC_ALL=C echo 'y' | LC_ALL=C pivpn -r #{wireguard_client.name}")
            Rails.logger.info "Removed client #{wireguard_client.name}: #{output}"
          end
          wireguard_client.update!(status: "revoked")
        rescue StandardError => e
          Rails.logger.error "Error revoking WireGuard client #{wireguard_client.name}: #{e.message}"
        end
      end
      subscription.update!(status: "expired")
    end
  end
end
