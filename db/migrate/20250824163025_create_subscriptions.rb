class CreateSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :wireguard_client, null: false, foreign_key: true
      t.string :status
      t.datetime :expires_at

      t.timestamps
    end
  end
end
