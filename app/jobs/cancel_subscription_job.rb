# app/jobs/cancel_subscription_job.rb
class CancelSubscriptionJob < ApplicationJob
  queue_as :default

  def perform(subscription_id)
    subscription = Subscription.find(subscription_id)
    Rails.logger.info "Cancelling subscription #{subscription.name}"

    StripeSessionExpirer.expire(subscription)
    SubscriptionRevocationService.new(subscription).revoke!
    subscription.update!(status: "canceled")

    Rails.logger.info "Successfully cancelled subscription #{subscription.name}"
  rescue => e
    Rails.logger.error "Failed to cancel subscription #{subscription_id}: #{e.message}"
    raise
  end
end
