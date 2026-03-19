# app/services/stripe_session_expirer.rb
class StripeSessionExpirer
  def self.expire(subscription)
    return unless subscription.stripe_session_id.present?

    session = Stripe::Checkout::Session.retrieve(subscription.stripe_session_id)
    Stripe::Checkout::Session.expire(subscription.stripe_session_id) if session.status == "open"
  rescue Stripe::InvalidRequestError
    Rails.logger.warn "Stripe session for #{subscription.name} already invalid — skipping"
  end
end
