# app/controllers/admin/servers_controller.rb
module Admin
  class ServersController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin

    def index
      @servers = Server.all
    end

    def new
      @server = Server.new
    end

    def create
      @server = Server.new(server_params)
      if @server.save
        redirect_to admin_servers_path, notice: "Server added successfully."
      else
        render :new
      end
    end

    def edit
      @server = Server.find(params[:id])
    end

    def update
      @server = Server.find(params[:id])
      if @server.update(server_params)
        redirect_to admin_servers_path, notice: "Server updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def require_admin
      unless current_user.admin?
        redirect_to root_path, alert: "Access denied."
      end
    end

    def server_params
      params.require(:server).permit(
        :name, :ip_address, :ssh_user, :ssh_password,
        :wireguard_server_ip, :wireguard_public_key, :max_subscriptions, :active
      )
    end
  end
end
