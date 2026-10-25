require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  setup do
    @user = create_user(email: "client@example.com")
    @subscription = create_subscription(user: @user, plan: create_plan(name: "Monthly"))
  end

  test "subscription_expired" do
    mail = UserMailer.subscription_expired(@user, @subscription)

    assert_equal ["client@example.com"], mail.to
    assert_equal "Your Vulcain VPN subscription has expired", mail.subject
    body = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s
    assert_includes body, @subscription.name
    assert_includes body, "Monthly"
    assert_includes body, "https://www.vulcainvpn.com/dashboard"
  end
end
