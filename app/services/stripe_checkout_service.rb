# app/services/stripe_checkout_service.rb
class StripeCheckoutService
  def initialize(subscription)
    @subscription = subscription
    @user = subscription.user
  end

  def create_session
    host = Rails.application.routes.default_url_options[:host]
    Stripe::Checkout::Session.create(
      payment_method_types: ['card'],
      mode: 'payment', # one-time payment
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: "#{@subscription.plan.name} Plan",
            description: @subscription.plan.description
          },
          unit_amount: (@subscription.price * 100).to_i # Stripe expects cents
        },
        quantity: 1
      }],
      customer_email: @user.email,
      success_url: Rails.application.routes.url_helpers.user_subscription_url(@user, @subscription, host: host) + "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: Rails.application.routes.url_helpers.new_user_subscription_url(@user, host: host),
      automatic_tax: { enabled: false }
    )
  end
end
