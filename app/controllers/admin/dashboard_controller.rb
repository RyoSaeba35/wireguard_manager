# app/controllers/admin/dashboard_controller.rb
module Admin
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    def index
      # Users
      @total_users = User.count
      @active_users = User.joins(:subscriptions).where(subscriptions: { status: 'active' }).distinct.count

      # Subscriptions
      @total_subscriptions = Subscription.where(status: ['active', 'expired']).count
      @active_subscriptions = Subscription.active.count
      @expired_subscriptions = Subscription.expired.count
      @pending_subscriptions = Subscription.where(status: ['pending', 'payment_pending']).count

      # Weekly subscriptions
      @weekly_subscriptions = Subscription.joins(:plan)
                                          .where(status: ['active', 'expired'])
                                          .where(plans: { interval: 'week' })
                                          .count

      # Monthly subscriptions
      @monthly_subscriptions_total = Subscription.joins(:plan)
                                                .where(status: ['active', 'expired'])
                                                .where(plans: { interval: 'month' })
                                                .count

      # Subscriptions by time period
      @subscriptions_today = Subscription.where(status: ['active', 'expired'])
                                          .where('created_at >= ?', Time.current.beginning_of_day)
                                          .count
      @subscriptions_this_month = Subscription.where(status: ['active', 'expired'])
                                              .where('created_at >= ?', Time.current.beginning_of_month)
                                              .count
      @subscriptions_this_year = Subscription.where(status: ['active', 'expired'])
                                            .where('created_at >= ?', Time.current.beginning_of_year)
                                            .count

      # ⭐ Server & Capacity Metrics (Pooling)
      @total_servers = Server.active.count
      @healthy_servers = Server.active.healthy.count
      @total_capacity = Server.active.healthy.sum(:max_concurrent_connections)
      @safe_subscription_limit = SystemSetting.max_active_subscriptions
      @current_connections = VpnConfigSet.where(status: 'in_use').count
      @capacity_utilization = (@total_capacity > 0) ? (@current_connections.to_f / @total_capacity * 100).round(2) : 0
      @capacity_percent = @capacity_utilization # Alias for view compatibility

      # ⭐ NEW: Devices
      @total_devices = Device.count

      # ⭐ Capacity breakdown
      @capacity_stats = SystemSetting.capacity_stats
      @subscription_capacity_used = @safe_subscription_limit > 0 ? (@active_subscriptions.to_f / @safe_subscription_limit * 100).round(1) : 0

      # ⭐ Pool health
      @total_pool_configs = VpnConfigSet.count
      @available_configs = VpnConfigSet.where(status: 'available').count
      @in_use_configs = VpnConfigSet.where(status: 'in_use').count
      @used_configs = VpnConfigSet.where(status: 'used').count

      # ⭐ NEW: System health status
      status_info = system_health_check
      @system_status = status_info[:status]
      @system_status_message = format_system_status(status_info)

      # ⭐ NEW: Detailed per-server status
      @servers_status = Server.active.map do |server|
        connections = VpnConfigSet.where(server_id: server.id, status: 'in_use').count
        {
          name: server.name,
          flag: server.flag || '🌐',
          healthy: server.healthy?,
          connections: connections,
          capacity: server.max_concurrent_connections,
          load_percent: server.max_concurrent_connections > 0 ? (connections.to_f / server.max_concurrent_connections * 100).round(1) : 0
        }
      end

      # Server load distribution (existing - good!)
      @server_load_data = Server.active.map do |s|
        current = s.vpn_config_sets.where(status: 'in_use').count
        max = s.max_concurrent_connections
        {
          name: s.name,
          location: s.location || s.name,
          load: max > 0 ? (current.to_f / max * 100).round(1) : 0,
          current: current,
          max: max,
          healthy: s.healthy?
        }
      end

      # Monthly subscriptions for the past 12 months
      @monthly_subscriptions = (0..11).map do |i|
        month_start = Time.current.beginning_of_month - i.months
        month_end = Time.current.beginning_of_month - (i - 1).months
        {
          month: month_start,
          count: Subscription.where(status: ['active', 'expired'])
                             .where(created_at: month_start..month_end)
                             .count
        }
      end.sort_by { |m| m[:month] }

      # Plan popularity
      @plan_popularity = Plan.joins(:subscriptions)
                             .where(subscriptions: { status: ['active', 'expired'] })
                             .group('plans.name')
                             .count

      # ⭐ NEW: Recent activity
      @recent_subscriptions = Subscription.order(created_at: :desc)
                                          .limit(10)
                                          .includes(:user, :plan)

      @plans = Plan.all.order(:price)
      @servers = Server.all
    end

    private

    def require_admin!
      unless current_user.admin?
        redirect_to root_path, alert: "You are not authorized to access this page."
      end
    end

    # ⭐ NEW: System health check
    def system_health_check
      all_servers = Server.active
      healthy_servers = all_servers.where(healthy: true)

      total_servers = all_servers.count
      healthy_count = healthy_servers.count

      total_capacity = healthy_servers.sum(:max_concurrent_connections)
      current_connections = VpnConfigSet.where(
        server_id: healthy_servers.pluck(:id),
        status: 'in_use'
      ).count

      capacity_percent = total_capacity > 0 ? (current_connections.to_f / total_capacity * 100).round(1) : 0

      max_subscriptions = SystemSetting.max_active_subscriptions
      current_subscriptions = Subscription.active.count
      subscription_percent = max_subscriptions > 0 ? (current_subscriptions.to_f / max_subscriptions * 100).round(1) : 0

      {
        total_servers: total_servers,
        healthy_servers: healthy_count,
        total_capacity: total_capacity,
        current_connections: current_connections,
        capacity_percent: capacity_percent,
        subscription_percent: subscription_percent,
        status: determine_status(healthy_count, total_servers, capacity_percent, subscription_percent)
      }
    end

    # ⭐ NEW: Determine overall system status
    def determine_status(healthy_count, total_servers, capacity_percent, subscription_percent)
      server_health_percent = total_servers > 0 ? (healthy_count.to_f / total_servers * 100).round(1) : 0

      return "CRITICAL" if server_health_percent < 50
      return "AT_CAPACITY" if capacity_percent >= 90 || subscription_percent >= 95
      return "WARNING" if server_health_percent < 80 || capacity_percent >= 70 || subscription_percent >= 85
      "OK"
    end

    # ⭐ NEW: Format status message
    def format_system_status(status_info)
      case status_info[:status]
      when "OK"
        "All systems operational (#{status_info[:healthy_servers]}/#{status_info[:total_servers]} servers, #{status_info[:capacity_percent]}% capacity)"
      when "WARNING"
        warnings = []
        server_health = (status_info[:healthy_servers].to_f / status_info[:total_servers] * 100).round(1)
        warnings << "#{status_info[:total_servers] - status_info[:healthy_servers]} server(s) down" if server_health < 80
        warnings << "#{status_info[:capacity_percent]}% capacity used" if status_info[:capacity_percent] >= 70
        warnings << "#{status_info[:subscription_percent]}% subscriptions active" if status_info[:subscription_percent] >= 85
        "System running with reduced capacity: #{warnings.join(', ')}"
      when "AT_CAPACITY"
        "System at capacity (#{status_info[:capacity_percent]}% connections, #{status_info[:subscription_percent]}% subscriptions)"
      when "CRITICAL"
        "Multiple servers offline (#{status_info[:healthy_servers]}/#{status_info[:total_servers]} healthy) - immediate action required"
      end
    end
  end
end
