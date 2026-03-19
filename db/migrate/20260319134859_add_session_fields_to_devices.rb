class AddSessionFieldsToDevices < ActiveRecord::Migration[7.2]
  def change
    add_column :devices, :connected_at, :datetime
    add_column :devices, :last_heartbeat_at, :datetime
  end
end
