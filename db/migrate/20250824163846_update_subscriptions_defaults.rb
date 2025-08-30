class UpdateSubscriptionsDefaults < ActiveRecord::Migration[7.2]
  def change
    change_column :subscriptions, :status, :string, default: "active"
    change_column_null :subscriptions, :expires_at, false
  end
end

