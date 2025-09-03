class WireguardClient < ApplicationRecord
  # Association with User
  belongs_to :subscription

  validates :name, uniqueness: true
  validates :ip_address, uniqueness: true, allow_nil: true
  validates :public_key, presence: true
  validates :private_key, presence: true

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def display_name
    parts = name.split('_')
    if parts.size == 2
      "Device #{parts.last}"
    else
      name
    end
  end

  # Optional: Delegate subscription's user for convenience
  delegate :user, to: :subscription, allow_nil: true
end
