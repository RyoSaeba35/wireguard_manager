# db/migrate/XXXXXXXXXXXXXX_allow_devices_without_subscriptions.rb
class AllowDevicesWithoutSubscriptions < ActiveRecord::Migration[7.0]
  def change
    # Allow subscription_id to be null in devices table
    change_column_null :devices, :subscription_id, true

    # Add index for faster queries
    add_index :devices, [:user_id, :subscription_id], if_not_exists: true
  end
end
