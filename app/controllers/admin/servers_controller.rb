# app/controllers/admin/servers_controller.rb
module Admin
  class ServersController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :set_server, only: [:edit, :update, :show, :destroy, :toggle_active, :rebuild_pool]

    def index
      @servers = Server.all.order(created_at: :desc)

      # ⭐ NEW: Calculate system-wide pooling metrics
      @total_capacity = Server.active.where(healthy: true).sum(:max_concurrent_connections)
      @active_connections = VpnConfigSet.where(status: 'in_use').count
    end

    def show
      # Server details page (optional - for viewing metrics)
      @active_connections = @server.vpn_config_sets.in_use.count
      @available_configs = @server.vpn_config_sets.available.count
      @used_configs = @server.vpn_config_sets.used.count
      @total_configs = @server.vpn_config_sets.count
    end

    def new
      @server = Server.new
      # Set default values
      @server.max_concurrent_connections = 225
      @server.config_pool_size = 3000
      @server.wireguard_port = 53050
      @server.singbox_hysteria2_port = 8443
      @server.singbox_ss_port = 443
      @server.active = true
    end

    def create
      @server = Server.new(server_params)

      if @server.save
        # ⭐ Create config pool in background
        CreateConfigPoolJob.perform_later(@server.id, @server.config_pool_size)

        redirect_to admin_servers_path,
                    notice: "Server created successfully. Generating #{@server.config_pool_size} config sets in background..."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      # @server set by before_action
    end

    def update
      # Remove blank password fields to preserve existing values
      %i[ssh_password singbox_salamander_password singbox_ss_master_password clash_api_secret ssh_private_key].each do |field|
        params[:server].delete(field) if params[:server][field].blank?
      end

      if @server.update(server_params)
        redirect_to edit_admin_server_path(@server),
                    notice: "Server updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      server_name = @server.name

      # This will cascade delete all vpn_config_sets and vpn_connections
      @server.destroy

      redirect_to admin_servers_path,
                  notice: "Server '#{server_name}' and all associated configs deleted."
    end

    # ⭐ NEW: Toggle server active/inactive
    def toggle_active
      @server.update!(active: !@server.active)

      status = @server.active ? "activated" : "deactivated"
      redirect_to admin_servers_path,
                  notice: "#{@server.name} has been #{status}."
    end

    # ⭐ NEW: Rebuild server's entire config pool
    def rebuild_pool
      pool_size = @server.config_pool_size

      # Delete all existing configs for this server
      destroyed_count = @server.vpn_config_sets.destroy_all.count

      # Recreate pool in background
      CreateConfigPoolJob.perform_later(@server.id, pool_size)

      redirect_to edit_admin_server_path(@server),
                  notice: "Deleted #{destroyed_count} old configs. Rebuilding pool of #{pool_size} configs in background..."
    end

    # Generate SSH key pair
    def generate_ssh_key
      require 'openssl'

      # Generate 4096-bit RSA key
      key = OpenSSL::PKey::RSA.new(4096)

      # Private key in PEM format
      private_key_pem = key.to_pem

      # Public key in OpenSSH format
      public_key_ssh = "#{key.ssh_type} #{[key.to_blob].pack('m0')}".strip

      render json: {
        private_key: private_key_pem,
        public_key: public_key_ssh
      }
    end

    private

    def set_server
      @server = Server.find(params[:id])
    end

    def require_admin
      unless current_user.admin?
        redirect_to root_path, alert: "Access denied."
      end
    end

    def server_params
      params.require(:server).permit(
        # Basic info
        :name,
        :ip_address,
        :active,

        # Location (for server selection)
        :location,
        :city,
        :country_code,
        :flag,
        :latitude,
        :longitude,

        # Capacity & pooling
        :max_concurrent_connections,
        :config_pool_size,

        # WireGuard
        :wireguard_server_ip,
        :wireguard_public_key,
        :wireguard_port,

        # Sing-box
        :singbox_active,
        :singbox_server_name,
        :singbox_salamander_password,
        :singbox_ss_master_password,
        :singbox_ss_port,
        :singbox_hysteria2_port,
        :clash_api_secret,

        # SSH authentication
        :ssh_user,
        :ssh_password,
        :ssh_private_key,
        :ssh_public_key
      )
    end
  end
end
