# app/jobs/revoke_expired_subscriptions_job.rb
class RevokeExpiredSubscriptionsJob < ApplicationJob
  queue_as :default

  def perform
    Subscription.where("expires_at < ? AND status = ?", Time.current, "active").each do |subscription|
      # Revoke the WireGuard client
      wireguard_client = subscription.wireguard_client
      wireguard_client.update(status: "revoked")

      # Update the subscription status
      subscription.update(status: "expired")

      # # Optionally: Remove the client from the WireGuard server via SSH
      # Net::SSH.start(ENV['RASPBERRY_PI_IP'], ENV['RASPBERRY_PI_USER'], password: ENV['RASPBERRY_PI_PASSWORD']) do |ssh|
      #   ssh.exec!("sudo wg set wg0 peer #{wireguard_client.public_key} remove")
      # end
    end
  end
end
