# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Clear existing data to avoid duplicates
WireguardClient.destroy_all
Subscription.destroy_all
User.destroy_all
Plan.destroy_all

# Helper method to generate random 6-character alphanumeric uppercase strings
def random_name
  (0...6).map { ('A'..'Z').to_a[rand(26)] }.join
end

# Create plans
Plan.create!([
  {
    name: "Pay as you go - Week",
    price: 5.95,
    interval: "week",
    active: true,
    description: "Unlimited Bandwidth, France Server Access, Advanced Encryption, Up to 3 Devices Simultaneously, No Long-Term Commitment"
  },
  {
    name: "Pay as you go - Month",
    price: 24.95,
    interval: "month",
    active: true,
    description: "Unlimited Bandwidth, France Server Access, Advanced Encryption, Up to 3 Devices Simultaneously, No Long-Term Commitment"
  },
  {
    name: "Pay as you go - Year",
    price: 249.99,
    interval: "year",
    active: true,
    description: "Unlimited Bandwidth, France Server Access, Advanced Encryption, Up to 3 Devices Simultaneously, No Long-Term Commitment"
  }
])

puts "Plans created successfully!"

# Create admin user
admin = User.create!(
  email: "pedro89@hotmail.fr",
  password: "12345678",
  password_confirmation: "12345678",
  admin: true,
  reset_password_token: nil,
  reset_password_sent_at: nil,
  remember_created_at: nil
)
puts "Admin user created: #{admin.email}"

# Counter for unique IP addresses
ip_counter = 1

# Create 5 regular users
5.times do |i|
  user = User.create!(
    email: "user#{i+1}@example.com",
    password: 'password123',
    password_confirmation: 'password123',
    reset_password_token: nil,
    reset_password_sent_at: nil,
    remember_created_at: nil
  )

  # Active subscription
  active_plan = Plan.find_by(interval: "month")
  active_subscription = Subscription.create!(
    user: user,
    status: 'active',
    expires_at: DateTime.now + 1.month,
    name: random_name,
    price: active_plan.price,
    plan_id: active_plan.id
  )

  # 2 Inactive subscriptions
  2.times do |k|
    inactive_plan = Plan.find_by(interval: "week")
    inactive_subscription = Subscription.create!(
      user: user,
      status: 'inactive',
      expires_at: DateTime.now - 1.month,
      name: random_name,
      price: inactive_plan.price,
      plan_id: inactive_plan.id
    )

    # 3 WireGuard clients for active subscription (only for the first inactive subscription)
    if k == 0
      3.times do |j|
        WireguardClient.create!(
          name: "#{active_subscription.name}_#{j+1}",
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

    # 3 WireGuard clients for inactive subscription
    3.times do |j|
      WireguardClient.create!(
        name: "#{inactive_subscription.name}_#{j+1}",
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

puts "Seed data created successfully: 1 admin, 5 users, each with 1 active and 2 inactive subscriptions, and 9 WireGuard clients!"
