# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    # Fetch the "active" subscription, but only if it's truly not expired
    @active_subscription = current_user.subscriptions.find_by(
      status: "active",
      expires_at: Time.current..Float::INFINITY  # Only subscriptions that expire in the future
    )

    # Fetch all expired subscriptions (for the "Expired Subscriptions" section)
    @expired_subscriptions = current_user.subscriptions.where("expires_at < ?", Time.current)

    # Set @has_subscription based on whether there's a truly active subscription
    @has_subscription = @active_subscription.present?
  end

  def setup
    @has_subscription = current_user.subscriptions.active.any?
    @active_subscription = current_user.subscriptions.active.first
  end
end
