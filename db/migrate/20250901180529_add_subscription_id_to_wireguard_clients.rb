class AddSubscriptionIdToWireguardClients < ActiveRecord::Migration[7.2]
  def change
    add_reference :wireguard_clients, :subscription, null: false, foreign_key: true
    # Only add the index if it doesn't exist
    unless index_exists?(:wireguard_clients, :subscription_id)
      add_index :wireguard_clients, :subscription_id
    end
  end
end
