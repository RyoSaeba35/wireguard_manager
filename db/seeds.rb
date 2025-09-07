# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
# db/seeds.rb

# Clear existing data to avoid duplicates
puts "Clearing existing data..."
WireguardClient.destroy_all
Subscription.destroy_all
User.destroy_all
Plan.destroy_all
Server.destroy_all
Setting.destroy_all

# Helper method to generate random 6-character alphanumeric uppercase strings
def random_name
  (0...6).map { ('A'..'Z').to_a[rand(26)] }.join
end

# Create plans
Plan.find_or_create_by(name: "Pay as you go - Week") do |plan|
  plan.update!(
    price: 5.95,
    interval: "week",
    active: true,
    description: "Unlimited Bandwidth, France Server Access, Advanced Encryption, Up to 3 Devices Simultaneously, No Long-Term Commitment"
  )
end

Plan.find_or_create_by(name: "Pay as you go - Month") do |plan|
  plan.update!(
    price: 24.95,
    interval: "month",
    active: true,
    description: "Unlimited Bandwidth, France Server Access, Advanced Encryption, Up to 3 Devices Simultaneously, No Long-Term Commitment"
  )
end

Plan.find_or_create_by(name: "Pay as you go - Year") do |plan|
  plan.update!(
    price: 249.99,
    interval: "year",
    active: true,
    description: "Unlimited Bandwidth, France Server Access, Advanced Encryption, Up to 3 Devices Simultaneously, No Long-Term Commitment"
  )
end
puts "Plans created successfully!"

# Create default server (for development)
Server.find_or_create_by(name: "Default VPN Server") do |server|
  server.update!(
    ip_address: ENV['RASPBERRY_PI_IP'],
    wireguard_server_ip: ENV['YOUR_SERVER_IP'],
    ssh_user: ENV['RASPBERRY_PI_USER'],
    ssh_password: ENV['RASPBERRY_PI_PASSWORD'],
    wireguard_public_key: ENV['YOUR_SERVER_PUBLIC_KEY'],
    max_subscriptions: 50,
    current_subscriptions: 0,
    active: true
  )
end
puts "Default server created!"

# Create admin user
admin = User.find_or_create_by(email: "pedro89@hotmail.fr") do |user|
  user.update!(
    password: "12345678",
    password_confirmation: "12345678",
    admin: true,
    reset_password_token: nil,
    reset_password_sent_at: nil,
    remember_created_at: nil
  )
end
puts "Admin user created: #{admin.email}"

# Counter for unique IP addresses
ip_counter = 200

# Create 5 regular users
5.times do |i|
  user = User.find_or_create_by(email: "user#{i+1}@example.com") do |u|
    u.update!(
      password: 'password123',
      password_confirmation: 'password123',
      reset_password_token: nil,
      reset_password_sent_at: nil,
      remember_created_at: nil
    )
  end

  # Active subscription
  active_plan = Plan.find_by(interval: "month")
  active_subscription = Subscription.find_or_create_by(user: user, status: 'active') do |sub|
    sub.update!(
      expires_at: DateTime.now + 1.month,
      name: random_name,
      price: active_plan.price,
      plan_id: active_plan.id,
      server: Server.first
    )
  end

  # Update server's current_subscriptions counter
  if active_subscription.server
    active_subscription.server.update!(
      current_subscriptions: active_subscription.server.subscriptions.where(status: 'active').count
    )
  end

  # 3 WireGuard clients for active subscription
  3.times do |j|
    WireguardClient.find_or_create_by(name: "#{active_subscription.name}_#{j+1}") do |client|
      client.update!(
        public_key: "PUBLIC_KEY_#{j+1}",
        private_key: "PRIVATE_KEY_#{j+1}",
        ip_address: "10.0.0.#{ip_counter}",
        expires_at: DateTime.now + 6.months,
        status: 'active',
        subscription: active_subscription
      )
      ip_counter += 1
    end
  end

  # 2 Inactive subscriptions
  2.times do |k|
    inactive_plan = Plan.find_by(interval: "week")
    inactive_subscription = Subscription.find_or_create_by(
      user: user,
      status: 'inactive',
      name: "#{random_name}_INACTIVE_#{k+1}"
    ) do |sub|
      sub.update!(
        expires_at: DateTime.now - 1.month,
        price: inactive_plan.price,
        plan_id: inactive_plan.id,
        server: Server.first
      )
    end

    # 3 WireGuard clients for inactive subscription
    3.times do |j|
      WireguardClient.find_or_create_by(name: "#{inactive_subscription.name}_#{j+1}") do |client|
        client.update!(
          public_key: "PUBLIC_KEY_#{j+1}",
          private_key: "PRIVATE_KEY_#{j+1}",
          ip_address: "10.0.0.#{ip_counter}",
          expires_at: DateTime.now - 1.month,
          status: 'inactive',
          subscription: inactive_subscription
        )
        ip_counter += 1
      end
    end
  end
end

puts "Seed data created successfully: 1 admin, 5 users, each with 1 active and 2 inactive subscriptions, and 9 WireGuard clients!"
puts "Default server is ready with #{Server.first.max_subscriptions} subscription slots."
