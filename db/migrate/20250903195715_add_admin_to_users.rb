# db/migrate/[timestamp]_add_admin_to_users.rb
class AddAdminToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :admin, :boolean, default: false
  end
end
