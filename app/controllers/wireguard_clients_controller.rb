class WireguardClientsController < ApplicationController
  before_action :authenticate_user!

  def new
    @wireguard_client = current_user.wireguard_clients.new
  end

  def create
    @wireguard_client = current_user.wireguard_clients.new(wireguard_client_params)

    if @wireguard_client.save
      # Generate the WireGuard config and QR code here
      redirect_to @wireguard_client, notice: 'WireGuard client was successfully created.'
    else
      render :new
    end
  end

  def show
    @wireguard_client = current_user.wireguard_clients.find(params[:id])
  end

  private

  def wireguard_client_params
    params.require(:wireguard_client).permit(:name, :public_key, :private_key, :ip_address)
  end
end
