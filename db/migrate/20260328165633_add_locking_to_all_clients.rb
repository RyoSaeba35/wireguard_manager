class AddLockingToAllClients < ActiveRecord::Migration[7.0]
  def change
    add_column :hysteria2_clients, :locked_at, :datetime
    add_column :hysteria2_clients, :locked_reason, :string

    add_column :shadowsocks_clients, :locked_at, :datetime
    add_column :shadowsocks_clients, :locked_reason, :string

    add_column :wireguard_clients, :locked_at, :datetime
    add_column :wireguard_clients, :locked_reason, :string
  end
end
