# db/migrate/[timestamp]_make_user_id_nullable_in_subscriptions.rb
class MakeUserIdNullableInSubscriptions < ActiveRecord::Migration[7.2]
  def change
    change_column_null :subscriptions, :user_id, true
  end
end
