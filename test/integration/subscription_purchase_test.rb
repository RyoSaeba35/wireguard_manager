require "test_helper"

class SubscriptionPurchaseTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  def sign_in_as(user)
    post "/users/sign_in", params: { user: { email: user.email, password: "Password123!" } }
  end

  test "a deactivated plan cannot be bought by sending its id" do
    old_plan = create_plan(interval: "month", price: 15, active: false)

    assert_no_difference -> { Subscription.count } do
      post "/users/#{@user.id}/subscriptions", params: { subscription: { plan_id: old_plan.id } }
    end
    assert_redirected_to new_user_subscription_path(@user)
  end
end
