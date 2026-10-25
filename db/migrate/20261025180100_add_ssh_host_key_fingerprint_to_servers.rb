# db/migrate/20261025180100_add_ssh_host_key_fingerprint_to_servers.rb
#
# Pinned SSH host key per server, see app/services/ssh_host_key_verifier.rb.
# Empty until the first connection after deploy (trust on first use).
class AddSshHostKeyFingerprintToServers < ActiveRecord::Migration[7.2]
  def change
    add_column :servers, :ssh_host_key_fingerprint, :string
  end
end
