class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    @user_ip = request.env['HTTP_X_FORWARDED_FOR'] || request.remote_ip
    @user_ip = @user_ip.to_s.strip
    @user_ip = @user_ip.gsub(/^::ffff:/, '') if @user_ip.include?('::ffff:')
    @vpn_server_ips = Rails.cache.fetch("active_vpn_server_ips", expires_in: 12.hours) do
      Server.where(active: true).pluck(:ip_address).map(&:to_s).map(&:strip)
    end
    @country = fetch_country(@user_ip)
    @active_subscription = current_user.subscriptions.find_by(
      status: "active",
      expires_at: Time.current..Float::INFINITY
    )
    @expired_subscriptions = current_user.subscriptions.where("expires_at < ?", Time.current)
    @has_subscription = @active_subscription.present?

    @user_server_ip = @active_subscription.server.ip_address if @has_subscription && @active_subscription&.server&.present?

    if @vpn_server_ips.include?(@user_ip) || (@user_server_ip.present? && @vpn_server_ips.include?(@user_server_ip))
      begin
        uri = URI.parse("http://#{@user_server_ip || @user_ip}/api/server-status")
        request = Net::HTTP::Get.new(uri)
        request.basic_auth('vulcainadmin', 'Vulcain1989!')

        response = Net::HTTP.start(uri.hostname, uri.port) do |http|
          http.request(request)
        end

        if response.code == "200"
          data = JSON.parse(response.body)
          @server_status = format_server_status(data)
        else
          @server_status = "Server status unavailable"
        end
      rescue StandardError => e
        Rails.logger.error("Failed to fetch server status: #{e.message}")
        @server_status = "Server status unavailable"
      end
    end
  end

  def setup
    @has_subscription = current_user.subscriptions.active.any?
    @active_subscription = current_user.subscriptions.active.first
  end

  def fetch_server_status
    response.headers["Cache-Control"] = "no-cache, no-store, max-age=0, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"
    @active_subscription = current_user.subscriptions.find_by(
      status: "active",
      expires_at: Time.current..Float::INFINITY
    )
    @has_subscription = @active_subscription.present?
    @user_server_ip = @active_subscription.server.ip_address if @has_subscription && @active_subscription&.server&.present?

    if (@user_server_ip.present? && @vpn_server_ips.include?(@user_server_ip))
      begin
        uri = URI.parse("http://#{@user_server_ip}/api/server-status")
        request = Net::HTTP::Get.new(uri)
        request.basic_auth('vulcainadmin', 'Vulcain1989!')

        response_api = Net::HTTP.start(uri.hostname, uri.port) do |http|
          http.request(request)
        end

        if response_api.code == "200"
          data = JSON.parse(response_api.body)
          render json: data
        else
          render json: { error: "Server status unavailable" }, status: :ok
        end
      rescue StandardError => e
        Rails.logger.error("Failed to fetch server status: #{e.message}")
        render json: { error: "Server status unavailable" }, status: :ok
      end
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

  def format_server_status(data)
    if data['status'] == "OK" || data['status'] == "WARNING"
      "VPN Service: All systems operational."
    else
      "VPN Service: Unavailable. We are experiencing technical difficulties."
    end
  end
end
