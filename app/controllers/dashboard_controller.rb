# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!, except: [:setup]

  def show
    @user_ip = request.env['HTTP_X_FORWARDED_FOR'] || request.remote_ip
    @user_ip = @user_ip.to_s.strip.gsub(/^::ffff:/, '')

    # ⭐ NEW: Get VPN server IPs for connection detection
    @vpn_server_ips = Rails.cache.fetch("active_vpn_server_ips", expires_in: 5.minutes) do
      Server.active.pluck(:ip_address).map(&:to_s).map(&:strip)
    end

    @country = fetch_country(@user_ip)
    @active_subscription = current_user.subscriptions.active.first
    @expired_subscriptions = current_user.subscriptions.expired
    @has_subscription = @active_subscription.present?

    # ⭐ NEW: Calculate overall system status
    if @has_subscription
      @active_devices = @active_subscription.devices.where(active: true)
      @current_connections = @active_subscription.vpn_connections.active.includes(:server)

      # Get system-wide status (not just one server)
      @server_status = calculate_system_status
    end
  end

  def setup
    if user_signed_in?
      @has_subscription = current_user.subscriptions.active.any?
      @active_subscription = current_user.subscriptions.active.first
    else
      @active_subscription = nil
      @has_subscription = false
    end
  end

  def fetch_server_status
    response.headers["Cache-Control"] = "no-cache, no-store, max-age=0, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"

    @active_subscription = current_user.subscriptions.active.first

    if @active_subscription
      # Return system-wide status
      status_info = system_health_check
      render json: status_info
    else
      render json: { no_subscription: true }, status: :ok
    end
  end

  private

  def fetch_country(ip)
    Rails.cache.fetch("country_#{ip}", expires_in: 1.hour) do
      response = Net::HTTP.get(URI("http://ip-api.com/json/#{ip}"))
      JSON.parse(response)['country']
    rescue StandardError
      nil
    end
  end

  # ⭐ NEW: Calculate overall system status
  def calculate_system_status
    # Cache for 2 minutes to avoid hammering servers
    Rails.cache.fetch("system_status", expires_in: 2.minutes) do
      status_info = system_health_check
      format_system_status(status_info)
    end
  end

  # ⭐ NEW: Check overall system health
  def system_health_check
    all_servers = Server.active
    healthy_servers = all_servers.where(healthy: true)

    total_servers = all_servers.count
    healthy_count = healthy_servers.count

    # Calculate capacity
    total_capacity = healthy_servers.sum(:max_concurrent_connections)
    current_connections = VpnConfigSet.where(
      server_id: healthy_servers.pluck(:id),
      status: 'in_use'
    ).count

    capacity_percent = total_capacity > 0 ? (current_connections.to_f / total_capacity * 100).round(1) : 0

    # Calculate subscription capacity
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

  # ⭐ NEW: Determine system status based on health and capacity
  def determine_status(healthy_count, total_servers, capacity_percent, subscription_percent)
    # Calculate server health percentage
    server_health_percent = total_servers > 0 ? (healthy_count.to_f / total_servers * 100).round(1) : 0

    # RED: Critical - Service degraded or at capacity
    if server_health_percent < 50
      return "CRITICAL" # More than half servers down
    elsif capacity_percent >= 90 || subscription_percent >= 95
      return "AT_CAPACITY" # Almost full
    end

    # YELLOW: Warning - Service degraded
    if server_health_percent < 80
      return "WARNING" # Some servers down
    elsif capacity_percent >= 70 || subscription_percent >= 85
      return "WARNING" # Getting full
    end

    # GREEN: All good
    "OK"
  end

  # ⭐ NEW: Format status for display
  def format_system_status(status_info)
    case status_info[:status]
    when "OK"
      if status_info[:healthy_servers] == status_info[:total_servers]
        "VPN Service: All systems operational. (#{status_info[:healthy_servers]} servers, #{status_info[:capacity_percent]}% capacity)"
      else
        "VPN Service: Operational. (#{status_info[:healthy_servers]}/#{status_info[:total_servers]} servers, #{status_info[:capacity_percent]}% capacity)"
      end

    when "WARNING"
      warnings = []

      server_health = (status_info[:healthy_servers].to_f / status_info[:total_servers] * 100).round(1)
      if server_health < 80
        warnings << "#{status_info[:total_servers] - status_info[:healthy_servers]} server(s) down"
      end

      if status_info[:capacity_percent] >= 70
        warnings << "#{status_info[:capacity_percent]}% capacity used"
      end

      if status_info[:subscription_percent] >= 85
        warnings << "#{status_info[:subscription_percent]}% subscriptions active"
      end

      "VPN Service: Running with reduced capacity. (#{warnings.join(', ')})"

    when "AT_CAPACITY"
      "VPN Service: At capacity. New connections may be delayed. (#{status_info[:capacity_percent]}% full)"

    when "CRITICAL"
      "VPN Service: Service degraded. Multiple servers offline. Please contact support."

    else
      "VPN Service: Status unavailable."
    end
  end
end
