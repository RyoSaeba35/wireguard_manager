class Admin::ConnectionsController < ApplicationController
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
    # Trigger disconnect on server if needed
    redirect_to admin_connections_path, notice: "Connection disconnected"
  end
end
