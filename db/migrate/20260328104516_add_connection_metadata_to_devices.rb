class AddConnectionMetadataToDevices < ActiveRecord::Migration[7.2]
  def change
    add_column :devices, :last_connection_ip, :inet
    add_column :devices, :last_protocol_type, :string
  end
end
