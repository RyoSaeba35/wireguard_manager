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

    # Get first client to test with
    test_client = WireguardClient.where(preshared_key: nil).first

    unless test_client
      puts "✅ All clients already have PSKs!"
      exit 0
    end

    server = test_client.subscription.server
    private_key_path = write_private_key(server)

    puts "Testing SSH connection to #{server.ip_address} as #{server.ssh_user}..."

    begin
      Net::SSH.start(
        server.ip_address,
        server.ssh_user,
        keys: [private_key_path],
        verify_host_key: :never,
        non_interactive: true,
        timeout: 30,
        auth_methods: ['publickey']
      ) do |ssh|
        result = ssh.exec!("whoami")
        puts "✅ SSH connection successful! Logged in as: #{result.strip}"
      end
    rescue Net::SSH::AuthenticationFailed => e
      puts "❌ SSH Authentication Failed!"
      puts "   The private key in the database doesn't match the server's authorized_keys"
      puts "   Error: #{e.message}"
      File.delete(private_key_path)
      exit 1
    rescue => e
      puts "❌ SSH Connection Error: #{e.class}"
      puts "   #{e.message}"
      File.delete(private_key_path)
      exit 1
    end

    File.delete(private_key_path)
    puts "="*60

    # Now backfill all clients
    WireguardClient.where(preshared_key: nil).find_each do |client|
      total += 1
      server = client.subscription.server
      private_key_path = nil

      begin
        private_key_path = write_private_key(server)

        puts "📡 #{client.name}..."

        Net::SSH.start(
          server.ip_address,
          server.ssh_user,
          keys: [private_key_path],
          verify_host_key: :never,
          non_interactive: true,
          auth_methods: ['publickey']
        ) do |ssh|
          config_path = "/home/#{server.ssh_user}/configs/#{client.name}.conf"

          # Check if file exists
          file_check = ssh.exec!("test -f #{config_path} && echo 'yes' || echo 'no'").strip

          if file_check == 'no'
            puts "   ⚠️  Config file not found"
            errors += 1
            next
          end

          # Fetch PSK
          psk_line = ssh.exec!("grep 'PresharedKey' #{config_path} 2>/dev/null || true").strip

          if psk_line.empty?
            puts "   ⚠️  No PresharedKey in config"
            errors += 1
            next
          end

          preshared_key = psk_line.split('=').last.strip

          if preshared_key.length > 20  # Sanity check
            client.update!(preshared_key: preshared_key)
            puts "   ✅ #{preshared_key[0..15]}..."
            updated += 1
          else
            puts "   ⚠️  Invalid PSK format"
            errors += 1
          end
        end

      rescue => e
        puts "   ❌ #{e.message}"
        errors += 1
      ensure
        File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
      end
    end

    puts "="*60
    puts "Total: #{total} | Updated: #{updated} | Errors: #{errors}"
    puts "="*60
  end
end
