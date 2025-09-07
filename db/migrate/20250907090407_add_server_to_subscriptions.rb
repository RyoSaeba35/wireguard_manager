# db/migrate/[timestamp]_add_server_to_subscriptions.rb
class AddServerToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_reference :subscriptions, :server, foreign_key: true
  end
end
