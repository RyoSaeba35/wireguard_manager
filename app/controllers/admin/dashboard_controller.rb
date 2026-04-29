# app/controllers/admin/dashboard_controller.rb
module Admin
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    def index
      # ============================================
      # OPTIMIZED: Users (2 queries instead of many)
      # ============================================
      @total_users = User.count
      @active_users = User.joins(:subscriptions)
                         .where(subscriptions: { status: 'active' })
                         .distinct
                         .count

      # ============================================
      # OPTIMIZED: Subscriptions - ONE grouped query instead of 4+
      # ============================================
      subscription_stats = Subscription.group(:status).count
      @active_subscriptions = subscription_stats['active'] || 0
      @expired_subscriptions = subscription_stats['expired'] || 0
      @pending_subscriptions = (subscription_stats['pending'] || 0) + (subscription_stats['payment_pending'] || 0)
      @total_subscriptions = @active_subscriptions + @expired_subscriptions

      # ============================================
      # OPTIMIZED: Subscriptions by interval - ONE query
      # ============================================
      interval_stats = Subscription.joins(:plan)
                                  .where(status: ['active', 'expired'])
                                  .group('plans.interval')
                                  .count
      @weekly_subscriptions = interval_stats['week'] || 0
      @monthly_subscriptions_total = interval_stats['month'] || 0

      # ============================================
      # OPTIMIZED: Subscriptions by time - 3 queries with better conditions
      # ============================================
      today_start = Time.current.beginning_of_day
      month_start = Time.current.beginning_of_month
      year_start = Time.current.beginning_of_year

      @subscriptions_today = Subscription.where(status: ['active', 'expired'])
                                        .where('created_at >= ?', today_start)
                                        .count
      @subscriptions_this_month = Subscription.where(status: ['active', 'expired'])
                                              .where('created_at >= ?', month_start)
                                              .count
      @subscriptions_this_year = Subscription.where(status: ['active', 'expired'])
                                            .where('created_at >= ?', year_start)
                                            .count

      # ============================================
      # OPTIMIZED: Server & Capacity - efficient queries
      # ============================================
      @total_servers = Server.active.count
      @healthy_servers = Server.active.where(healthy: true).count
      @total_capacity = Server.active.where(healthy: true).sum(:max_concurrent_connections)
      @safe_subscription_limit = SystemSetting.max_active_subscriptions

      # ============================================
      # OPTIMIZED: Pool health - ONE grouped query instead of 4
      # ============================================
      pool_stats = VpnConfigSet.group(:status).count
      @available_configs = pool_stats['available'] || 0
      @in_use_configs = pool_stats['in_use'] || 0
      @used_configs = pool_stats['used'] || 0
      @total_pool_configs = VpnConfigSet.count

      # Current connections (already have this from pool stats)
      @current_connections = @in_use_configs
      @capacity_utilization = (@total_capacity > 0) ? (@current_connections.to_f / @total_capacity * 100).round(2) : 0
      @capacity_percent = @capacity_utilization

      # Devices
      @total_devices = Device.count

      # Capacity stats
      @capacity_stats = SystemSetting.capacity_stats
      @subscription_capacity_used = @safe_subscription_limit > 0 ?
        (@active_subscriptions.to_f / @safe_subscription_limit * 100).round(1) : 0

      # ============================================
      # OPTIMIZED: System health - use already calculated values
      # ============================================
      @system_status, @system_status_message = calculate_system_status

      # ============================================
      # OPTIMIZED: Per-server status - ONE query with subselect (eliminates N+1)
      # ============================================
      servers_with_counts = Server.active.select(
        'servers.*',
        '(SELECT COUNT(*) FROM vpn_config_sets
          WHERE vpn_config_sets.server_id = servers.id
          AND vpn_config_sets.status = \'in_use\') as connections_count'
      )

      @servers_status = servers_with_counts.map do |server|
        connections = server.connections_count || 0
        capacity = server.max_concurrent_connections || 0
        {
          name: server.name,
          flag: server.flag || '🌐',
          healthy: server.healthy?,
          connections: connections,
          capacity: capacity,
          load_percent: capacity > 0 ? (connections.to_f / capacity * 100).round(1) : 0
        }
      end

      # Server load data (same optimization)
      @server_load_data = servers_with_counts.map do |server|
        connections = server.connections_count || 0
        capacity = server.max_concurrent_connections || 0
        {
          name: server.name,
          location: server.location || server.name,
          load: capacity > 0 ? (connections.to_f / capacity * 100).round(1) : 0,
          current: connections,
          max: capacity,
          healthy: server.healthy?
        }
      end

      # ============================================
      # OPTIMIZED: Monthly subscriptions - ONE query with GROUP BY
      # ============================================
      twelve_months_ago = 12.months.ago.beginning_of_month

      # Get all monthly counts in one query
      monthly_counts = Subscription
        .where(status: ['active', 'expired'])
        .where('created_at >= ?', twelve_months_ago)
        .group("DATE_TRUNC('month', created_at)")
        .count

      # Build array with all 12 months (fill gaps with 0)
      @monthly_subscriptions = (0..11).map do |i|
        month_start = Time.current.beginning_of_month - i.months
        {
          month: month_start,
          count: monthly_counts[month_start] || 0
        }
      end.reverse

      # ============================================
      # OPTIMIZED: Plan popularity - already efficient
      # ============================================
      @plan_popularity = Plan.joins(:subscriptions)
                             .where(subscriptions: { status: ['active', 'expired'] })
                             .group('plans.name')
                             .count

      # ============================================
      # OPTIMIZED: Recent activity - proper includes to prevent N+1
      # ============================================
      @recent_subscriptions = Subscription.includes(:user, :plan)
                                          .order(created_at: :desc)
                                          .limit(10)

      # Plans and servers (already efficient)
      @plans = Plan.order(:price)
      @servers = Server.all
    end

    private

    def require_admin!
      unless current_user.admin?
        redirect_to root_path, alert: "You are not authorized to access this page."
      end
    end

    # ============================================
    # OPTIMIZED: Use already calculated values instead of re-querying
    # ============================================
    def calculate_system_status
      server_health_percent = @total_servers > 0 ?
        (@healthy_servers.to_f / @total_servers * 100).round(1) : 0

      # Determine status
      status = if server_health_percent < 50
        "CRITICAL"
      elsif @capacity_percent >= 90 || @subscription_capacity_used >= 95
        "AT_CAPACITY"
      elsif server_health_percent < 80 || @capacity_percent >= 70 || @subscription_capacity_used >= 85
        "WARNING"
      else
        "OK"
      end

      # Format message
      message = case status
      when "OK"
        "All systems operational (#{@healthy_servers}/#{@total_servers} servers, #{@capacity_percent}% capacity)"
      when "WARNING"
        warnings = []
        warnings << "#{@total_servers - @healthy_servers} server(s) down" if server_health_percent < 80
        warnings << "#{@capacity_percent}% capacity used" if @capacity_percent >= 70
        warnings << "#{@subscription_capacity_used}% subscriptions active" if @subscription_capacity_used >= 85
        "System running with reduced capacity: #{warnings.join(', ')}"
      when "AT_CAPACITY"
        "System at capacity (#{@capacity_percent}% connections, #{@subscription_capacity_used}% subscriptions)"
      when "CRITICAL"
        "Multiple servers offline (#{@healthy_servers}/#{@total_servers} healthy) - immediate action required"
      end

      [status, message]
    end
  end
end
