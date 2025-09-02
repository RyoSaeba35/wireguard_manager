class RemoveWireguardClientIdFromSubscriptions < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :subscriptions, :wireguard_clients
    remove_index :subscriptions, :wireguard_client_id
    remove_column :subscriptions, :wireguard_client_id, :integer
  end
end
