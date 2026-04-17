# app/services/subscription_revocation_service.rb
class SubscriptionRevocationService
  def initialize(subscription)
    @subscription = subscription
  end

  def revoke!
    Rails.logger.info "Starting revocation for subscription #{@subscription.name}"

    ActiveRecord::Base.transaction do
      # 1. Release all active configs back to pool
      released_count = 0
      @subscription.devices.each do |device|
        next unless device.vpn_config_set

        if device.vpn_config_set.status == 'in_use'
          device.vpn_config_set.release!
          released_count += 1
          Rails.logger.info "Released config #{device.vpn_config_set.ip_address} from device #{device.name}"
        end
      end

      # 2. Close all active VPN connections
      closed_count = 0
      @subscription.vpn_connections.active.each do |connection|
        connection.update!(disconnected_at: Time.current)
        closed_count += 1
      end

      # 3. Deactivate all devices
      @subscription.devices.update_all(active: false)

      # 4. Update subscription status
      @subscription.update!(
        status: 'expired',
        expires_at: Time.current
      )

      Rails.logger.info "✅ Revoked subscription #{@subscription.name}: " \
                        "released #{released_count} configs, " \
                        "closed #{closed_count} connections"
    end

    true
  rescue => e
    Rails.logger.error "Failed to revoke subscription #{@subscription.name}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  # Optional: Soft revoke (keeps devices, just disconnects)
  def soft_revoke!
    Rails.logger.info "Soft revoking subscription #{@subscription.name}"

    # Just disconnect active connections, don't release configs
    @subscription.vpn_connections.active.update_all(disconnected_at: Time.current)
    @subscription.update!(status: 'expired')

    Rails.logger.info "✅ Soft revoked subscription #{@subscription.name}"
  end
end
