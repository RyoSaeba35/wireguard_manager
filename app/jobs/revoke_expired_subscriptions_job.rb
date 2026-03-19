# app/jobs/revoke_expired_subscriptions_job.rb
class RevokeExpiredSubscriptionsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  def perform
    start_time = Time.current
    Rails.logger.info "Starting RevokeExpiredSubscriptionsJob at #{start_time}"

    Subscription.where("expires_at < ? AND status = ?", Time.current, "active")
                .limit(BATCH_SIZE)
                .find_each do |subscription|
      process_subscription(subscription)
    end

    Rails.logger.info "Completed RevokeExpiredSubscriptionsJob in #{(Time.current - start_time).round(2)}s"
  end

  private

  def process_subscription(subscription)
    Rails.logger.info "Processing expired subscription #{subscription.name}"

    subscription.update!(status: "expired")
    SubscriptionRevocationService.new(subscription).revoke!
    notify_user(subscription)

    Rails.logger.info "Successfully processed expired subscription #{subscription.name}"
  rescue => e
    Rails.logger.error "Failed to process subscription #{subscription.name}: #{e.message}"
    subscription.update!(status: "expired") rescue nil
  end

  def notify_user(subscription)
    SubscriptionMailer.subscription_expired(subscription).deliver_later
  rescue => e
    Rails.logger.error "Failed to send expiry email for #{subscription.name}: #{e.message}"
  end
end
