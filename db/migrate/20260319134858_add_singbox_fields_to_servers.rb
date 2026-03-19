class AddSingboxFieldsToServers < ActiveRecord::Migration[7.2]
  def change
    add_column :servers, :singbox_active, :boolean, default: false
    add_column :servers, :singbox_server_name, :string
    add_column :servers, :singbox_salamander_password, :string
    add_column :servers, :singbox_ss_master_password, :string
    add_column :servers, :singbox_ss_port, :integer, default: 443
    add_column :servers, :singbox_hysteria2_port, :integer, default: 8443
  end
end
