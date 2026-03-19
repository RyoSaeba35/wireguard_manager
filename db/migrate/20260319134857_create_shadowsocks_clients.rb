class CreateShadowsocksClients < ActiveRecord::Migration[7.2]
  def change
    create_table :shadowsocks_clients do |t|
      t.references :subscription, null: false, foreign_key: true
      t.references :device, null: true, foreign_key: true
      t.string :name, null: false
      t.string :password, null: false
      t.string :status, default: "preallocated"
      t.datetime :expires_at
      t.datetime :connected_at
      t.timestamps
    end

    add_index :shadowsocks_clients, :name, unique: true
    add_index :shadowsocks_clients, :status
  end
end
