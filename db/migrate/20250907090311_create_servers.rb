# db/migrate/[timestamp]_create_servers.rb
class CreateServers < ActiveRecord::Migration[7.2]
  def change
    create_table :servers do |t|
      t.string :name, null: false
      t.string :ip_address, null: false
      t.string :wireguard_server_ip, null: false
      t.string :wireguard_public_key
      t.integer :max_subscriptions, default: 0
      t.integer :current_subscriptions, default: 0
      t.boolean :active, default: true
      t.timestamps
    end
  end
end
