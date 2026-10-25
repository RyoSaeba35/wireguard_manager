require "test_helper"

class StripeWebhooksTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @subscription = create_subscription(
      user: @user,
      status: "payment_pending",
      stripe_session_id: "cs_test_123",
      expires_at: 3.days.from_now # provisional value from checkout
    )
  end

  def stripe_event(type, object)
    Stripe::Event.construct_from(type: type, data: { object: object })
  end

  # Signature checking is Stripe's code; we only replace it here
  def deliver(event)
    Stripe::Webhook.stub(:construct_event, event) do
      post "/stripe/webhook", params: "{}", headers: { "Content-Type" => "application/json", "Stripe-Signature" => "t=1,v1=x" }
    end
  end

  test "checkout.session.completed activates the subscription and sends ONE welcome email" do
    assert_enqueued_emails 1 do
      deliver(stripe_event("checkout.session.completed", { id: "cs_test_123" }))
    end

    assert_response :ok
    @subscription.reload
    assert_equal "active", @subscription.status
    assert_in_delta (Time.current + 1.month + 2.hours).to_i, @subscription.expires_at.to_i, 60
  end

  test "a repeated webhook does not activate or email twice" do
    deliver(stripe_event("checkout.session.completed", { id: "cs_test_123" }))

    assert_no_enqueued_emails do
      deliver(stripe_event("checkout.session.completed", { id: "cs_test_123" }))
    end
  end

  test "checkout.session.expired marks the subscription failed" do
    deliver(stripe_event("checkout.session.expired", { id: "cs_test_123" }))
    assert_equal "failed", @subscription.reload.status
  end

  test "an invalid signature is rejected" do
    raising = ->(*) { raise Stripe::SignatureVerificationError.new("bad", "sig") }
    Stripe::Webhook.stub(:construct_event, raising) do
      post "/stripe/webhook", params: "{}", headers: { "Content-Type" => "application/json" }
    end
    assert_response :bad_request
    assert_equal "payment_pending", @subscription.reload.status
  end
end
