# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Clear existing data to avoid duplicates
WireguardClient.destroy_all
Subscription.destroy_all
User.destroy_all

# Helper method to generate random 6-character alphanumeric uppercase strings
def random_name
  (0...6).map { ('A'..'Z').to_a[rand(26)] }.join
end

# Create 5 users
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
  active_subscription = Subscription.create!(
    user: user,
    status: 'active',
    expires_at: DateTime.now + 1.month,
    name: random_name,
    price: 19.90,
    plan: 'Pay As You Go'
  )

  # 2 Inactive subscriptions
  2.times do |k|
    inactive_subscription = Subscription.create!(
      user: user,
      status: 'inactive',
      expires_at: DateTime.now - 1.month,
      name: random_name,
      price: 19.90,
      plan: 'Pay As You Go'
    )

    # 3 WireGuard clients for active subscription
    if k == 0
      3.times do |j|
        WireguardClient.create!(
          name: "#{active_subscription.name}_#{j+1}",
          public_key: "PUBLIC_KEY_#{j+1}",
          private_key: "PRIVATE_KEY_#{j+1}",
          ip_address: "10.0.0.#{i*6 + j + 1}",
          expires_at: DateTime.now + 6.months,
          status: 'active',
          subscription: active_subscription
        )
      end
    end

    # 3 WireGuard clients for inactive subscription
    3.times do |j|
      WireguardClient.create!(
        name: "#{inactive_subscription.name}_#{j+1}",
        public_key: "PUBLIC_KEY_#{j+1}",
        private_key: "PRIVATE_KEY_#{j+1}",
        ip_address: "10.0.0.#{i*6 + j + 4}",
        expires_at: DateTime.now - 1.month,
        status: 'inactive',
        subscription: inactive_subscription
      )
    end
  end
end

puts "Seed data created successfully: 5 users, each with 1 active and 2 inactive subscriptions, and 9 WireGuard clients!"
