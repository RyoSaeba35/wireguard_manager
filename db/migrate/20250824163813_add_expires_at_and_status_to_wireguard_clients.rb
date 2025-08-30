class AddExpiresAtAndStatusToWireguardClients < ActiveRecord::Migration[7.2]
  def change
    add_column :wireguard_clients, :expires_at, :datetime
    add_column :wireguard_clients, :status, :string, default: "active"
  end
end

