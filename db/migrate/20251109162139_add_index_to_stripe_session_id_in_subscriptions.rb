class AddIndexToStripeSessionIdInSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_index :subscriptions, :stripe_session_id, unique: true
  end
end
