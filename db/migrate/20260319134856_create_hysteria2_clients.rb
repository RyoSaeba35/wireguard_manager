class CreateHysteria2Clients < ActiveRecord::Migration[7.2]
  def change
    create_table :hysteria2_clients do |t|
      t.references :subscription, null: false, foreign_key: true
      t.references :device, null: true, foreign_key: true
      t.string :name, null: false
      t.string :password, null: false
      t.string :status, default: "preallocated"
      t.datetime :expires_at
      t.datetime :connected_at
      t.timestamps
    end

    add_index :hysteria2_clients, :name, unique: true
    add_index :hysteria2_clients, :status
  end
end
