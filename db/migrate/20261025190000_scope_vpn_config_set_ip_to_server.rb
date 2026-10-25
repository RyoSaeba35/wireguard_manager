# db/migrate/20261025190000_scope_vpn_config_set_ip_to_server.rb
#
# Tunnel addresses (10.155.x.x) only need to be unique PER SERVER: each server
# runs its own separate WireGuard network, and every server allocates from the
# same 10.155.0.0/16 range. The old index made them unique across all servers,
# so building the pool for a second server failed on its very first address.
class ScopeVpnConfigSetIpToServer < ActiveRecord::Migration[7.2]
  def change
    remove_index :vpn_config_sets, :ip_address, unique: true, name: "index_vpn_config_sets_on_ip_address"
    add_index :vpn_config_sets, [:server_id, :ip_address], unique: true,
              name: "index_vpn_config_sets_on_server_id_and_ip_address"
  end
end
