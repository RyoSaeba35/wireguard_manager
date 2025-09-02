# db/migrate/[timestamp]_remove_user_id_from_wireguard_clients.rb
class RemoveUserIdFromWireguardClients < ActiveRecord::Migration[7.2]
  def change
    remove_column :wireguard_clients, :user_id, :integer
  end
end

