# app/jobs/preallocate_subscriptions_job.rb
class PreallocateSubscriptionsJob < ApplicationJob
  include WireguardClientCreator
  include SingboxClientCreator
  queue_as :default

  def perform(server_id = nil)
    servers = if server_id
      [Server.find(server_id)]
    else
      Server.where(active: true).where("current_subscriptions < max_subscriptions")
    end

    servers.each do |server|
      preallocate_for_server(server)
    end
  end

  private

  def preallocate_for_server(server)
    target_pool_size = calculate_target_pool_size(server)
    current_preallocated = server.subscriptions.preallocated.count

    Rails.logger.info "Server #{server.name}: target=#{target_pool_size}, current=#{current_preallocated}"

    if current_preallocated >= target_pool_size
      Rails.logger.info "Server #{server.name} pool is healthy — skipping"
      ensure_singbox_matches_wireguard(server)
      return
    end

    default_plan = Plan.where(active: true).first
    unless default_plan
      Rails.logger.warn "No active plan found — skipping #{server.name}"
      return
    end

    private_key_path = nil
    singbox_reloaded = false

    private_key_path = write_private_key(server)

    Net::SSH.start(server.ip_address, server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|
      (current_preallocated...target_pool_size).each do
        preallocate_one(ssh, server, default_plan)
      end

      if server.singbox_active?
        validate_and_reload_singbox(ssh, server)
        singbox_reloaded = true
      end
    end

    Rails.logger.info "Server #{server.name}: pool topped up to #{target_pool_size} — sing-box reloaded: #{singbox_reloaded}"

  rescue Net::SSH::Exception => e
    Rails.logger.error "SSH failed for #{server.name}: #{e.message}"
  ensure
    File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
  end

  def preallocate_one(ssh, server, plan)
    subscription_name = unique_subscription_name(server)

    subscription = server.subscriptions.create!(
      name: subscription_name,
      status: "preallocated",
      plan: plan,
      price: plan.price,
      expires_at: 1.month.from_now,
      user_id: nil
    )

    CLIENTS_PER_SUBSCRIPTION.times do |i|
      client_name = "#{subscription_name}_#{i + 1}"
      create_client_on_server(ssh, client_name, subscription, server)
    end

    if server.singbox_active?
      create_singbox_clients(ssh, subscription, server)
    end

    Rails.logger.info "Pre-allocated subscription #{subscription_name} with WireGuard + sing-box clients"

  rescue => e
    Rails.logger.error "Failed to preallocate #{subscription_name}: #{e.message}"
    subscription&.destroy!
  end

  def ensure_singbox_matches_wireguard(server)
    return unless server.singbox_active?

    wg_count = server.subscriptions.preallocated
                     .joins(:wireguard_clients)
                     .distinct.count

    sb_count = server.subscriptions.preallocated
                     .joins(:hysteria2_clients)
                     .distinct.count

    if wg_count != sb_count
      Rails.logger.warn "Server #{server.name}: WireGuard pool (#{wg_count}) != sing-box pool (#{sb_count}) — rebalancing"

      missing = server.subscriptions.preallocated.select do |sub|
        sub.hysteria2_clients.empty?
      end

      return if missing.empty?

      private_key_path = nil

      private_key_path = write_private_key(server)

      Net::SSH.start(server.ip_address, server.ssh_user, keys: [private_key_path], verify_host_key: :never) do |ssh|
        missing.each do |sub|
          create_singbox_clients(ssh, sub, server)
        end
        validate_and_reload_singbox(ssh, server)
      end

      Rails.logger.info "Rebalanced sing-box pool for #{server.name}"
    else
      Rails.logger.info "Server #{server.name}: pools are in sync (#{wg_count} each)"
    end
  rescue => e
    Rails.logger.error "Failed to rebalance sing-box pool for #{server.name}: #{e.message}"
  ensure
    File.delete(private_key_path) if private_key_path && File.exist?(private_key_path)
  end

  def calculate_target_pool_size(server)
    available_capacity = server.max_subscriptions - server.current_subscriptions
    minimum_pool = (server.max_subscriptions * 0.7).to_i
    capacity_based = (server.max_subscriptions * 0.2).to_i
    demand_based = Subscription.where(
      server: server,
      status: "active",
      created_at: 1.day.ago.all_day
    ).count * 2

    target = [minimum_pool, capacity_based, demand_based].max
    [target, available_capacity].min
  end

  def unique_subscription_name(server)
    loop do
      name = SecureRandom.alphanumeric(5).upcase
      break name unless server.subscriptions.exists?(name: name)
    end
  end
end
