# app/models/vpn_config_set.rb
class VpnConfigSet < ApplicationRecord
  belongs_to :server
  belongs_to :device, optional: true
  has_many :vpn_connections

  # Statuses: available, in_use, used, recycling
  validates :status, inclusion: { in: %w[available in_use used recycling] }
  validates :ip_address, presence: true, uniqueness: true

  scope :available, -> { where(status: 'available') }
  scope :in_use, -> { where(status: 'in_use') }
  scope :used, -> { where(status: 'used') }

  # Claim this config for a device
  def claim!(device)
    transaction do
      update!(
        status: 'in_use',
        device: device,
        claimed_at: Time.current,
        last_used_at: Time.current
      )
    end
  end

  # Release back to pool
  def release!
    update!(
      status: 'used',
      device: nil,
      last_used_at: Time.current
    )
  end

  # Mark as available after recycling
  def recycle!
    update!(
      status: 'available',
      device: nil
    )
  end
end
