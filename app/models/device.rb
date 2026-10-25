# app/models/device.rb
class Device < ApplicationRecord
  belongs_to :user
  # ✅ optional: true - a device can exist before the user has a subscription.
  # Rails 7.2 makes belongs_to required by default, which made
  # POST /api/devices/register fail with "Subscription must exist" for
  # users without one, contradicting the "registration always allowed" rule.
  # The subscription check happens at /connect instead.
  belongs_to :subscription, optional: true

  # NEW: Pooling associations
  has_one :vpn_config_set, -> { where(status: 'in_use') }
  has_many :vpn_connections

  before_create :generate_api_key

  # Helper to get current active connection
  def current_connection
    vpn_connections.active.last
  end

  private

  def generate_api_key
    self.api_key ||= SecureRandom.hex(32)
  end
end
