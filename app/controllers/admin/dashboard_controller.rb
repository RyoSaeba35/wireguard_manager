# app/controllers/admin/dashboard_controller.rb
module Admin
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    def index
      @users = User.all.includes(:subscriptions)
      @active_subscriptions = Subscription.active.order(expires_at: :desc)
      @expired_subscriptions = Subscription.expired.order(expires_at: :desc)
      @wireguard_clients = WireguardClient.all.includes(:subscription)
    end

    private

    def require_admin!
      unless current_user.admin?
        redirect_to root_path, alert: "You are not authorized to access this page."
      end
    end
  end
end
