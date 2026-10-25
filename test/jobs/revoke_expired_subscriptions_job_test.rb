require "test_helper"

class RevokeExpiredSubscriptionsJobTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @server = create_server
  end

  test "expires the subscription, frees its configs and emails the user" do
    subscription = create_subscription(user: @user)
    subscription.update_column(:expires_at, 1.hour.ago)
    device = create_device(user: @user, subscription: subscription, active: true)
    config = create_config_set(server: @server, status: "in_use", device: device)

    assert_enqueued_email_with UserMailer, :subscription_expired, args: [@user, subscription] do
      RevokeExpiredSubscriptionsJob.perform_now
    end

    assert_equal "expired", subscription.reload[:status]
    assert_equal "used", config.reload.status
    assert_not device.reload.active
  end

  test "leaves subscriptions that are still running alone" do
    subscription = create_subscription(user: @user, expires_at: 1.week.from_now)

    assert_no_enqueued_emails do
      RevokeExpiredSubscriptionsJob.perform_now
    end
    assert_equal "active", subscription.reload[:status]
  end
end
