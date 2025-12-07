# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    @user_ip = request.env['HTTP_X_FORWARDED_FOR'] || request.remote_ip
    @vpn_server_ips = Rails.cache.fetch("active_vpn_server_ips", expires_in: 12.hours) do
      Server.where(active: true).pluck(:wireguard_server_ip)
    end
    @country = fetch_country(@user_ip)

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

  private

  def fetch_country(ip)
    Rails.cache.fetch("country_#{ip}", expires_in: 1.hour) do
      response = Net::HTTP.get(URI("http://ip-api.com/json/#{ip}"))
      JSON.parse(response)['country']
    rescue StandardError
      nil
    end
  end
end
