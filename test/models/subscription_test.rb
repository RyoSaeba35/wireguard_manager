require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @plan = create_plan(interval: "month")
  end

  test "activate! starts the paid period at activation, not at checkout" do
    subscription = nil
    travel_to Time.zone.local(2026, 10, 1, 10, 0, 0) do
      # Checkout opened on Oct 1st...
      subscription = create_subscription(
        user: @user, plan: @plan, status: "payment_pending",
        expires_at: Subscription.expiry_from("month")
      )
    end

    travel_to Time.zone.local(2026, 10, 1, 18, 0, 0) do
      # ...but paid 8 hours later
      subscription.activate!
      assert_equal "active", subscription.reload.status
      assert_in_delta (Time.current + 1.month + 2.hours).to_i, subscription.expires_at.to_i, 1
    end
  end

  test "activate! sends the welcome email exactly once, even if called twice" do
    subscription = create_subscription(user: @user, plan: @plan, status: "payment_pending")

    assert_enqueued_emails 1 do
      assert subscription.activate!
      assert_not subscription.activate!, "second call must be a no-op"
    end
  end

  test "expiry_from adds the plan period plus the 2 hour grace" do
    now = Time.zone.local(2026, 1, 1, 12)
    assert_equal now + 1.week + 2.hours,  Subscription.expiry_from("week",  from: now)
    assert_equal now + 1.month + 2.hours, Subscription.expiry_from("month", from: now)
    assert_equal now + 1.year + 2.hours,  Subscription.expiry_from("year",  from: now)
    assert_equal now + 1.month + 2.hours, Subscription.expiry_from(nil,     from: now)
  end

  test "status reports expired once an active subscription is past its date" do
    subscription = create_subscription(user: @user, plan: @plan, expires_at: 1.month.from_now)
    subscription.update_column(:expires_at, 1.minute.ago)

    assert_equal "expired", subscription.reload.status
    assert_not subscription.active?
  end
end
