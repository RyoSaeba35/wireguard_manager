# lib/tasks/wireguard.rake
namespace :wireguard do
  desc "Backfill preshared keys for existing WireGuard clients"
  task backfill_preshared_keys: :environment do
    require 'net/ssh'
    require 'tempfile'

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

    # Group clients by server to reuse SSH connections
    clients_by_server = WireguardClient.where(preshared_key: nil)
                                       .includes(:subscription)
                                       .group_by { |c| c.subscription.server }

    if clients_by_server.empty?
      puts "✅ All clients already have PSKs!"
      exit 0
    end

    # Process each server's clients in one SSH session
    clients_by_server.each do |server, clients|
      puts "\n🔧 Processing #{clients.count} clients on #{server.name}..."
      puts "   Server: #{server.ip_address}"

      private_key_path = write_private_key(server)

      begin
        # ⭐ Single SSH connection for all clients on this server
        Net::SSH.start(
          server.ip_address,
          server.ssh_user,
          keys: [private_key_path],
          verify_host_key: :never,
          non_interactive: true,
          auth_methods: ['publickey'],
          keepalive: true,
          keepalive_interval: 60
        ) do |ssh|

          puts "   ✅ SSH connected as #{ssh.exec!('whoami').strip}"
          puts "   " + "-"*56

          # Process all clients for this server in this single connection
          clients.each do |client|
            total += 1

            begin
              print "   📡 #{client.name.ljust(20)}"

              config_path = "/home/#{server.ssh_user}/configs/#{client.name}.conf"

              # Check if file exists
              file_check = ssh.exec!("test -f #{config_path} && echo 'yes' || echo 'no'").strip

              if file_check == 'no'
                puts "⚠️  Config not found"
                errors += 1
                next
              end

              # Fetch PSK
              psk_line = ssh.exec!("grep 'PresharedKey' #{config_path} 2>/dev/null || true").strip

              if psk_line.empty?
                puts "⚠️  No PSK in config"
                errors += 1
                next
              end

              preshared_key = psk_line.split('=').last.strip

              if preshared_key.length > 20
                client.update!(preshared_key: preshared_key)
                puts "✅ #{preshared_key[0..15]}..."
                updated += 1
              else
                puts "⚠️  Invalid PSK"
                errors += 1
              end

            rescue => e
              puts "❌ #{e.message[0..40]}"
              errors += 1
            end
          end
        end

        puts "   " + "-"*56
        puts "   ✅ Completed #{server.name}\n"

      rescue Net::SSH::AuthenticationFailed => e
        puts "   ❌ Authentication failed for #{server.name}"
        puts "      Error: #{e.message}"
        errors += clients.count
      rescue => e
        puts "   ❌ Connection error for #{server.name}"
        puts "      #{e.class}: #{e.message}"
        errors += clients.count
      ensure
        File.delete(private_key_path) if File.exist?(private_key_path)
      end
    end

    puts "="*60
    puts "📊 Summary:"
    puts "   Total clients: #{total}"
    puts "   ✅ Updated: #{updated}"
    puts "   ❌ Errors: #{errors}"
    puts "="*60

    if errors > 0
      puts "\n💡 Tip: Re-run this task to retry failed clients"
    end
  end
end
