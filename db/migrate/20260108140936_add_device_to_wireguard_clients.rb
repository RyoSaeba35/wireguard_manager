class AddDeviceToWireguardClients < ActiveRecord::Migration[7.2]
  def change
    add_reference :wireguard_clients, :device, foreign_key: true
  end
end
