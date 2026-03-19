# app/jobs/expire_abandoned_subscriptions_job.rb
class ExpireAbandonedSubscriptionsJob < ApplicationJob
  queue_as :default

  def perform
    Subscription.where(status: ["pending", "payment_pending"])
                .where("created_at < ?", 1.hour.ago)
                .find_each do |subscription|
      process_subscription(subscription)
    end
  end

  private

  def process_subscription(subscription)
    Rails.logger.info "Reclaiming abandoned subscription #{subscription.name}"

    # Expire Stripe session if still open
    StripeSessionExpirer.expire(subscription)

    # Safety check — should never have active devices at this stage
    # but guard against edge cases
    if subscription.devices.where(active: true).any?
      Rails.logger.warn "Subscription #{subscription.name} has active devices despite being abandoned — doing full revocation"
      SubscriptionRevocationService.new(subscription).revoke!
      subscription.update!(status: "canceled")
      return
    end

    # Return to pool — no SSH needed, clients untouched
    subscription.update!(
      user_id: nil,
      status: "preallocated",
      stripe_session_id: nil
    )

    Rails.logger.info "Successfully returned #{subscription.name} to preallocated pool"
  rescue => e
    Rails.logger.error "Failed to reclaim subscription #{subscription.name}: #{e.message}"
    # Last resort — mark canceled so it doesn't get stuck in pending forever
    subscription.update!(status: "canceled") rescue nil
  end
end
