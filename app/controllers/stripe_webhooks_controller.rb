class StripeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token # Stripe sends POST requests, not from a form
  skip_before_action :authenticate_user!

  def create
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

    event = nil

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError => e
      puts "Invalid payload: #{e.message}"
      render json: { error: "Invalid payload" }, status: 400
      return
    rescue Stripe::SignatureVerificationError => e
      puts "Invalid signature: #{e.message}"
      render json: { error: "Invalid signature" }, status: 400
      return
    end

    case event.type
    when 'checkout.session.completed'
      handle_checkout_session_completed(event.data.object)
    when 'checkout.session.expired'
      handle_checkout_session_expired(event.data.object)
    when 'payment_intent.payment_failed'
      handle_payment_failed(event.data.object)
    else
      puts "Unhandled event type: #{event.type}"
    end

    render json: { message: "Success" }, status: 200
  end

  private

  def handle_checkout_session_completed(session)
    subscription = Subscription.find_by(stripe_session_id: session.id)
    return unless subscription

    # Update subscription status to 'active' if it's pending or payment_pending
    if ['pending', 'payment_pending'].include?(subscription.status)
      subscription.update!(status: 'pending')
      if subscription.wireguard_clients.any?
        UserMailer.vpn_config_ready(subscription.user, subscription).deliver_later
        subscription.update!(status: 'active')
      else
        WireguardClientCreationJob.perform_later(subscription.id)
        # Wait for 1.5 seconds before redirecting
        sleep(2.5)
        subscription.update!(status: 'active')
      end
      Rails.logger.info "Subscription #{subscription.id} activated via webhook"
    end
  end

  def handle_checkout_session_expired(session)
    subscription = Subscription.find_by(stripe_session_id: session.id)
    return unless subscription

    # Update subscription status to 'canceled' if it's pending or payment_pending
    if ['pending', 'payment_pending'].include?(subscription.status)
      subscription.update!(status: 'canceled')
      Rails.logger.info "Subscription #{subscription.id} canceled due to session expiration"
    end
  end

  def handle_payment_failed(payment_intent)
    session_id = payment_intent.metadata.checkout_session_id
    return unless session_id

    subscription = Subscription.find_by(stripe_session_id: session_id)
    return unless subscription

    # Update subscription status to 'failed' if it's pending or payment_pending
    if ['pending', 'payment_pending'].include?(subscription.status)
      subscription.update!(status: 'failed')
      Rails.logger.info "Subscription #{subscription.id} marked as failed due to payment failure"
      UserMailer.payment_failed(subscription.user, subscription).deliver_later
    end
  end
end
