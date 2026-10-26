ENV["RAILS_ENV"] ||= "test"
# devise-jwt reads the secret at boot, so it must be set before loading Rails
ENV["DEVISE_JWT_SECRET_KEY"] ||= "test-only-jwt-secret-#{'x' * 48}"

require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

# Small builders instead of YAML fixtures: each test creates exactly the
# records it needs, with valid defaults that can be overridden.
module TestFactories
  def create_user(email: nil, password: "Password123!", **attrs)
    user = User.new(
      email: email || "user-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      **attrs
    )
    user.skip_confirmation!
    user.save!
    user
  end

  def create_plan(interval: "month", **attrs)
    Plan.create!(
      name: "Plan #{SecureRandom.hex(3)}",
      price: 9.99,
      interval: interval,
      active: true,
      description: "3 devices, No logs, France server", # pricing cards split it on ", "
      **attrs
    )
  end

  def create_subscription(user:, plan: nil, status: "active", expires_at: 1.month.from_now, **attrs)
    plan ||= create_plan
    Subscription.create!(
      user: user,
      plan: plan,
      status: status,
      expires_at: expires_at,
      name: SecureRandom.alphanumeric(6).upcase,
      price: plan.price,
      max_devices: 3,
      **attrs
    )
  end

  def create_server(**attrs)
    Server.create!({
      name: "srv-#{SecureRandom.hex(3)}",
      ip_address: "203.0.113.#{rand(1..254)}",
      wireguard_server_ip: "10.155.0.1",
      wireguard_public_key: "c2VydmVyLXB1YmxpYy1rZXktZm9yLXRlc3RzLW9ubHk=",
      wireguard_port: 53050,
      ssh_user: "ubuntu",
      active: true,
      healthy: true,
      max_concurrent_connections: 100,
      config_pool_size: 10
    }.merge(attrs))
  end

  def create_config_set(server:, status: "available", **attrs)
    @config_ip_counter = (@config_ip_counter || 1) + 1
    VpnConfigSet.create!({
      server: server,
      ip_address: "10.155.#{@config_ip_counter / 250}.#{(@config_ip_counter % 250) + 2}",
      wireguard_private_key: "priv-#{SecureRandom.hex(8)}",
      wireguard_public_key: "pub-#{SecureRandom.hex(8)}",
      wireguard_preshared_key: "psk-#{SecureRandom.hex(8)}",
      hysteria2_password: SecureRandom.hex(8),
      shadowsocks_password: SecureRandom.hex(8),
      status: status
    }.merge(attrs))
  end

  def create_device(user:, subscription: nil, **attrs)
    Device.create!({
      user: user,
      subscription: subscription,
      device_id: SecureRandom.uuid,
      platform: "android",
      name: "Test phone"
    }.merge(attrs))
  end

  # A valid access token, exactly as /api/login issues it
  def access_token_for(user)
    token, _payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    token
  end
end

module ActiveSupport
  class TestCase
    include TestFactories
    include ActiveJob::TestHelper
    include ActionMailer::TestHelper

    # Run tests in parallel with specified workers (each gets its own database)
    parallelize(workers: :number_of_processors)
  end
end

class ActionDispatch::IntegrationTest
  # The Flutter API only answers on the api. subdomain (see config/routes.rb)
  def use_api_host!
    host! "api.example.com"
  end

  def json
    JSON.parse(response.body)
  end
end
