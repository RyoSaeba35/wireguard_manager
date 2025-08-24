class CreateWireguardClients < ActiveRecord::Migration[7.2]
  def change
    create_table :wireguard_clients do |t|
      t.string :name
      t.text :public_key
      t.text :private_key
      t.string :ip_address
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
