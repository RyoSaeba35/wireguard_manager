# app/controllers/admin/servers_controller.rb
module Admin
  class ServersController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin

    def index
      @servers = Server.all
      @server_statuses = {}

      @servers.where(active: true).each do |server|
        begin
          uri = URI.parse("http://#{server.ip_address}/api/server-status")
          request = Net::HTTP::Get.new(uri)
          request.basic_auth('vulcainadmin', 'Vulcain1989!')

          response = Net::HTTP.start(uri.hostname, uri.port) do |http|
            http.request(request)
          end

          if response.code == "200"
            data = JSON.parse(response.body)
            @server_statuses[server.id] = data
          end
        rescue StandardError => e
          Rails.logger.error("Failed to fetch server status for #{server.ip_address}: #{e.message}")
          @server_statuses[server.id] = { status: "unavailable", error: "Failed to fetch status" }
        end
      end
    end

    def new
      @server = Server.new
    end

    def create
      @server = Server.new(server_params)
      if @server.save
        WireguardClientCreationJob.perform_later(@server.id)  # Enqueue the job after saving
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
        WireguardClientCreationJob.perform_later(@server.id)  # Enqueue the job after saving
        redirect_to admin_servers_path, notice: "Server updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def generate_ssh_key
      require 'openssl'
      key = OpenSSL::PKey::RSA.new(4096)
      private_key_pem = key.to_pem
      public_key_ssh = "#{key.ssh_type} #{[key.to_blob].pack('m0')}".strip

      render json: {
        private_key: private_key_pem,
        public_key: public_key_ssh
      }
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
        :wireguard_server_ip, :wireguard_public_key, :max_subscriptions, :active,
        :ssh_private_key, :ssh_public_key  # <-- Add these two lines
      )
    end
  end
end
