# lib/tasks/wireguard.rake
namespace :wireguard do
  desc "Backfill preshared keys for existing WireGuard clients"
  task backfill_preshared_keys: :environment do
    require 'net/ssh'
    require 'tempfile'

    # Helper method to write SSH private key to temp file
    def write_private_key(server)
      temp_file = Tempfile.new(['ssh_key', '.pem'])
      temp_file.write(server.ssh_private_key)
      temp_file.close
      File.chmod(0600, temp_file.path)
      temp_file.path
    end

    total = 0
    updated = 0
    errors = 0

    puts "Starting PSK backfill for WireGuard clients..."
    puts "="*60

    WireguardClient.where(preshared_key: nil).find_each do |client|
      total += 1
      server = client.subscription.server
      private_key_path = nil

      begin
        private_key_path = write_private_key(server)

        puts "📡 Fetching PSK for #{client.name} from #{server.name}..."

        Net::SSH.start(server.ip_address, server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|
          config_path = "/home/#{server.ssh_user}/configs/#{client.name}.conf"

          # Check if config file exists
          file_exists = ssh.exec!("test -f #{config_path} && echo 'yes' || echo 'no'").strip

          if file_exists == 'no'
            puts "⚠️  Config file not found: #{config_path}"
            errors += 1
            next
          end

          # Fetch PSK from server config
          preshared_key = ssh.exec!("cat #{config_path} | grep -A 5 '[Peer]' | grep 'PresharedKey' | head -n 1").chomp.split(' = ').last.strip

          if preshared_key.present?
            client.update!(preshared_key: preshared_key)
            puts "✅ Updated PSK for #{client.name}: #{preshared_key[0..15]}..."
            updated += 1
          else
            puts "⚠️  No PSK found in config for #{client.name}"
            errors += 1
          end
        end

      rescue => e
        puts "❌ Error updating #{client.name}: #{e.message}"
        puts "   #{e.backtrace.first}"
        errors += 1
      ensure
        File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
      end
    end

    puts "="*60
    puts "Backfill Summary:"
    puts "  Total clients processed: #{total}"
    puts "  Successfully updated: #{updated}"
    puts "  Errors: #{errors}"
    puts "="*60
  end
end
