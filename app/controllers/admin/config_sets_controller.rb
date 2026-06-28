# app/controllers/admin/config_sets_controller.rb
class Admin::ConfigSetsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def index
    @config_sets = VpnConfigSet.includes(:server).page(params[:page])
  end

  def available
    @config_sets = VpnConfigSet.available.includes(:server)
  end

  def in_use
    @config_sets = VpnConfigSet.in_use.includes(:server, :vpn_connections)
  end

  private

  def require_admin!
    unless current_user.admin?
      redirect_to root_path, alert: "You are not authorized to access this page."
    end
  end
end
