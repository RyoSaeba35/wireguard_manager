# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    @active_subscription = current_user.subscriptions.includes(:wireguard_client).find_by(status: "active")
    @expired_subscriptions = current_user.subscriptions.includes(:wireguard_client).where("expires_at < ?", Time.current)
    @has_subscription = @active_subscription.present?
  end
end

