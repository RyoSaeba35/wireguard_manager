class AddPresharedKeyToWireguardClients < ActiveRecord::Migration[7.2]
  def change
    add_column :wireguard_clients, :preshared_key, :text
  end
end
