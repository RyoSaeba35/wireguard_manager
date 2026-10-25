# db/migrate/20261025160000_add_singbox_tls_verified_to_servers.rb
#
# 🔐 Per-server switch for Hysteria2 certificate verification.
#
# false (default): the API tells clients tls_insecure = true, i.e. today's
#   behaviour. Nothing breaks when you deploy this.
# true: set it ONLY after the server's sing-box Hysteria2 inbound uses a real
#   certificate (e.g. Let's Encrypt) for servers.singbox_server_name. Clients
#   then verify the certificate and refuse a man-in-the-middle.
class AddSingboxTlsVerifiedToServers < ActiveRecord::Migration[7.2]
  def change
    add_column :servers, :singbox_tls_verified, :boolean, default: false, null: false
  end
end
