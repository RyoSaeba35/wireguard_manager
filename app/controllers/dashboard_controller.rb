# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    @active_subscription = current_user.subscriptions.find_by(status: "active")
    @expired_subscriptions = current_user.subscriptions.where("expires_at < ?", Time.current)
    @has_subscription = @active_subscription.present?
  end

  def setup
    @has_subscription = current_user.subscriptions.active.any?
    @active_subscription = current_user.subscriptions.active.first
  end
end
