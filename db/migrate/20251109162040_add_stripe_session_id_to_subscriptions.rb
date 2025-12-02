class AddStripeSessionIdToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :subscriptions, :stripe_session_id, :string
  end
end
