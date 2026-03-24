# Create a rake task: lib/tasks/backfill_preshared_keys.rake
namespace :wireguard do
  desc "Backfill preshared keys for existing WireGuard clients"
  task backfill_preshared_keys: :environment do
    WireguardClient.where(preshared_key: nil).find_each do |client|
      server = client.subscription.server

      begin
        private_key_path = write_private_key(server)  # Assuming you have this method

        Net::SSH.start(server.ip_address, server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|
          config_path = "/home/#{server.ssh_user}/configs/#{client.name}.conf"

          # Fetch PSK from server config
          preshared_key = ssh.exec!("cat #{config_path} | grep -A 5 '[Peer]' | grep 'PresharedKey' | head -n 1").chomp.split(' = ').last.strip

          if preshared_key.present?
            client.update!(preshared_key: preshared_key)
            puts "✅ Updated PSK for #{client.name}"
          else
            puts "⚠️  No PSK found for #{client.name}"
          end
        end
      rescue => e
        puts "❌ Error updating #{client.name}: #{e.message}"
      ensure
        File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
      end
    end
  end
end
