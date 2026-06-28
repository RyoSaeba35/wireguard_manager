# app/controllers/admin/connections_controller.rb
class Admin::ConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def index
    @connections = VpnConnection.includes(:vpn_config_set, :device, :user)
                                .order(created_at: :desc)
                                .page(params[:page])
  end

  def show
    @connection = VpnConnection.find(params[:id])
  end

  def active
    @connections = VpnConnection.active.includes(:vpn_config_set, :device)
  end

  def disconnect
    @connection = VpnConnection.find(params[:id])
    @connection.update!(disconnected_at: Time.current)
    redirect_to admin_connections_path, notice: "Connection disconnected"
  end

  private

  def require_admin!
    unless current_user.admin?
      redirect_to root_path, alert: "You are not authorized to access this page."
    end
  end
end
