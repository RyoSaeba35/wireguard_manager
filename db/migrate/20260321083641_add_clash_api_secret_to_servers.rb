class AddClashApiSecretToServers < ActiveRecord::Migration[7.2]
  def change
    add_column :servers, :clash_api_secret, :string
  end
end
