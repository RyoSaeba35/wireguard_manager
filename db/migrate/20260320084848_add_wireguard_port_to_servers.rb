class AddWireguardPortToServers < ActiveRecord::Migration[7.2]
  def change
    add_column :servers, :wireguard_port, :integer, default: 53050
  end
end
