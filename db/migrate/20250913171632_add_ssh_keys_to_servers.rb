class AddSshKeysToServers < ActiveRecord::Migration[7.2]
  def change
    add_column :servers, :ssh_public_key, :text
    add_column :servers, :ssh_private_key, :text
  end
end
