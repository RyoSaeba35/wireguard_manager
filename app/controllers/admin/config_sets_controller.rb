class Admin::ConfigSetsController < ApplicationController
  def index
    @config_sets = VpnConfigSet.includes(:server).page(params[:page])
  end

  def available
    @config_sets = VpnConfigSet.available.includes(:server)
  end

  def in_use
    @config_sets = VpnConfigSet.in_use.includes(:server, :vpn_connections)
  end
end
