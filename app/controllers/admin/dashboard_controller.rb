# app/controllers/admin/dashboard_controller.rb
module Admin
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    def index
      @total_users = User.count
      @active_users = User.joins(:subscriptions).where(subscriptions: { status: 'active' }).distinct.count
      @total_subscriptions = Subscription.count
      @active_subscriptions = Subscription.active.count
      # Weekly subscriptions (plans with 'week' interval)
      @weekly_subscriptions = Subscription.joins(:plan)
                                          .where(plans: { interval: 'week' })
                                          .count

      # Monthly subscriptions (plans with 'month' interval)
      @monthly_subscriptions_total = Subscription.joins(:plan)
                                                .where(plans: { interval: 'month' })
                                                .count
      @expired_subscriptions = Subscription.expired.count
      @pending_subscriptions = Subscription.where(status: ['pending', 'payment_pending']).count
      @total_servers = Server.where(active: true).count
      @total_server_capacity = Server.where(active: true).sum(:max_subscriptions)
      @used_server_capacity = Server.sum(:current_subscriptions)
      @server_load_percentage = (@total_server_capacity > 0) ? (@used_server_capacity.to_f / @total_server_capacity * 100).round(2) : 0

      # Subscriptions by time period
      @subscriptions_today = Subscription.where('created_at >= ?', Time.current.beginning_of_day).count
      @subscriptions_this_month = Subscription.where('created_at >= ?', Time.current.beginning_of_month).count
      @subscriptions_this_year = Subscription.where('created_at >= ?', Time.current.beginning_of_year).count

      # Monthly subscriptions for the past 12 months (sorted)
      @monthly_subscriptions = (0..11).map do |i|
        month_start = Time.current.beginning_of_month - i.months
        month_end = Time.current.beginning_of_month - (i - 1).months
        { month: month_start, count: Subscription.where(created_at: month_start..month_end).count }
      end.sort_by { |m| m[:month] } # Sort by date

      # Server load distribution
      @server_load_data = Server.all.map { |s| { name: s.name, load: s.current_subscriptions.to_f / s.max_subscriptions * 100 } }

      # Plan popularity
      @plan_popularity = Plan.joins(:subscriptions).group('plans.name').count

      @plans = Plan.all.order(:price)
      @servers = Server.all
    end


    private

    def require_admin!
      unless current_user.admin?
        redirect_to root_path, alert: "You are not authorized to access this page."
      end
    end
  end
end
