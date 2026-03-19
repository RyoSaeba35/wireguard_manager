# app/services/singbox_client_creator.rb
require 'json'

module SingboxClientCreator
  include SshKeyManager

  # Called once per subscription — no reload
  def create_singbox_clients(ssh, subscription, server)
    clients = ApplicationJob::CLIENTS_PER_SUBSCRIPTION.times.map do |i|
      client_name = "#{subscription.name}_#{i + 1}"

      if Hysteria2Client.exists?(name: client_name) && ShadowsocksClient.exists?(name: client_name)
        Rails.logger.info "Skipping existing sing-box client: #{client_name}"
        next
      end

      {
        name: client_name,
        hysteria2_password: generate_singbox_password,
        shadowsocks_password: generate_singbox_password
      }
    end.compact

    return if clients.empty?

    # Write all clients to config in one shot — no reload yet
    write_singbox_config(ssh, clients)

    # Save to DB
    clients.each do |client|
      Hysteria2Client.create!(
        name: client[:name],
        password: client[:hysteria2_password],
        subscription: subscription,
        status: "preallocated",
        expires_at: subscription.expires_at
      )

      ShadowsocksClient.create!(
        name: client[:name],
        password: client[:shadowsocks_password],
        subscription: subscription,
        status: "preallocated",
        expires_at: subscription.expires_at
      )
    end

    Rails.logger.info "Prepared #{clients.size} sing-box clients for #{subscription.name} — reload pending"
  rescue => e
    Rails.logger.error "Failed to create sing-box clients for #{subscription.name}: #{e.message}"
    raise
  end

  # Called once per server after ALL subscriptions are processed
  def validate_and_reload_singbox(ssh, server)
    check_output = ssh.exec!("sudo sing-box check -c /etc/sing-box/config.json 2>&1")

    if check_output.present? && check_output.include?("FATAL")
      Rails.logger.error "sing-box config validation failed for #{server.name}: #{check_output}"
      raise "sing-box config validation failed: #{check_output}"
    end

    ssh.exec!("sudo systemctl reload sing-box")
    Rails.logger.info "sing-box reloaded successfully for #{server.name}"
  end

  # Called when removing clients (subscription expired etc.)
  def remove_singbox_clients(ssh, subscription)
    client_names = subscription.hysteria2_clients.pluck(:name)
    return if client_names.empty?

    config_json = ssh.exec!("sudo cat /etc/sing-box/config.json")
    config = JSON.parse(config_json)

    hysteria2_inbound = config["inbounds"].find { |i| i["type"] == "hysteria2" }
    raise "Hysteria2 inbound not found in sing-box config" unless hysteria2_inbound

    ss_inbound = config["inbounds"].find { |i| i["type"] == "shadowsocks" }
    raise "Shadowsocks inbound not found in sing-box config" unless ss_inbound

    hysteria2_inbound["users"].reject! { |u| client_names.include?(u["name"]) }
    ss_inbound["users"].reject! { |u| client_names.include?(u["name"]) }

    write_config_to_server(ssh, config)

    Rails.logger.info "Removed sing-box clients for #{subscription.name} — reload pending"
  rescue => e
    Rails.logger.error "Failed to remove sing-box clients for #{subscription.name}: #{e.message}"
    raise
  end

  private

  def write_singbox_config(ssh, clients)
    config_json = ssh.exec!("sudo cat /etc/sing-box/config.json")
    config = JSON.parse(config_json)

    hysteria2_inbound = config["inbounds"].find { |i| i["type"] == "hysteria2" }
    raise "Hysteria2 inbound not found in sing-box config" unless hysteria2_inbound

    ss_inbound = config["inbounds"].find { |i| i["type"] == "shadowsocks" }
    raise "Shadowsocks inbound not found in sing-box config" unless ss_inbound

    clients.each do |client|
      hysteria2_inbound["users"] << {
        "name" => client[:name],
        "password" => client[:hysteria2_password]
      }

      ss_inbound["users"] << {
        "name" => client[:name],
        "password" => client[:shadowsocks_password]
      }
    end

    write_config_to_server(ssh, config)
  end

  def write_config_to_server(ssh, config)
    updated_config = JSON.pretty_generate(config)
    ssh.exec!("sudo tee /etc/sing-box/config.json > /dev/null << 'SINGBOX_EOF'\n#{updated_config}\nSINGBOX_EOF")
  end

  def generate_singbox_password
    SecureRandom.base64(32)
  end
end
