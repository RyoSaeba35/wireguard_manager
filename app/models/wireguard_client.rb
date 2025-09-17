class WireguardClient < ApplicationRecord
  belongs_to :subscription
  has_one_attached :config_file
  has_one_attached :qr_code
  validates :name, uniqueness: true
  validates :public_key, presence: true
  validates :private_key, presence: true
  validate :unique_active_ip_address

  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def display_name
    parts = name.split('_')
    parts.size == 2 ? "Device #{parts.last}" : name
  end

  delegate :user, to: :subscription, allow_nil: true

  private

  def unique_active_ip_address
    if ip_address.present? && WireguardClient.active.where(ip_address: ip_address).where.not(id: id).exists?
      errors.add(:ip_address, 'has already been taken by an active client')
    end
  end
end
