# app/models/vpn_connection.rb
class VpnConnection < ApplicationRecord
  belongs_to :user
  belongs_to :device
  belongs_to :config_set, class_name: 'VpnConfigSet'
  belongs_to :server

  # ⭐ ADD THIS ALIAS for easier access
  alias_attribute :vpn_config_set, :config_set

  validates :connected_at, presence: true

  scope :active, -> { where(disconnected_at: nil) }
  scope :completed, -> { where.not(disconnected_at: nil) }

  def duration_seconds
    return nil unless disconnected_at
    (disconnected_at - connected_at).to_i
  end

  def active?
    disconnected_at.nil?
  end
end
