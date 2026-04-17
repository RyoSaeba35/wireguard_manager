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
    Rails.logger.info "Expiring abandoned subscription #{subscription.name}"

    # Expire Stripe session if still open
    StripeSessionExpirer.expire(subscription)

    # ⭐ NEW: No pool to return to - just mark as failed
    subscription.update!(
      status: "failed",
      stripe_session_id: nil
    )

    Rails.logger.info "Marked abandoned subscription #{subscription.name} as failed"
  rescue => e
    Rails.logger.error "Failed to expire subscription #{subscription.name}: #{e.message}"
    subscription.update!(status: "failed") rescue nil
  end
end
