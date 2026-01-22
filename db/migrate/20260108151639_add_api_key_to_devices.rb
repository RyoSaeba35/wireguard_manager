class AddApiKeyToDevices < ActiveRecord::Migration[7.2]
  def change
    add_column :devices, :api_key, :string
    add_index :devices, :api_key, unique: true
  end
end
