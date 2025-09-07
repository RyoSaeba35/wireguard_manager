# db/migrate/[timestamp]_add_ssh_fields_to_servers.rb
class AddSshFieldsToServers < ActiveRecord::Migration[7.0]
  def change
    add_column :servers, :ssh_user, :string
    add_column :servers, :ssh_password, :string
  end
end
