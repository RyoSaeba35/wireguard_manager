class CreateDevices < ActiveRecord::Migration[7.2]
  def change
    create_table :devices do |t|
      t.references :user, null: false, foreign_key: true
      t.references :subscription, null: false, foreign_key: true

      t.string :device_id, null: false
      t.string :platform, null: false
      t.string :name

      t.boolean :active, default: false, null: false
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :devices, [:user_id, :device_id], unique: true
  end
end

