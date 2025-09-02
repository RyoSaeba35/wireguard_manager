class AddDetailsToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :subscriptions, :name, :string, null: false
    add_column :subscriptions, :price, :decimal, precision: 8, scale: 2, null: false
    add_column :subscriptions, :plan, :string, null: false
  end
end
