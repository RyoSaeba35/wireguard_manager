# app/models/device.rb
# app/models/device.rb
class Device < ApplicationRecord
  belongs_to :user
  belongs_to :subscription

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
