# db/migrate/[timestamp]_create_plans_and_update_subscriptions.rb
class CreatePlansAndUpdateSubscriptions < ActiveRecord::Migration[7.2]
  def change
    # Create the plans table
    create_table :plans do |t|
      t.string :name, null: false
      t.decimal :price, precision: 8, scale: 2, null: false
      t.string :interval, null: false
      t.boolean :active, default: true
      t.text :description
      t.timestamps
    end

    # Remove the plan column from subscriptions
    remove_column :subscriptions, :plan, :string

    # Add a foreign key to plans in subscriptions
    add_reference :subscriptions, :plan, foreign_key: true

    # Optional: Add plan_interval to subscriptions if you want to track the interval at subscription time
    add_column :subscriptions, :plan_interval, :string
  end
end
