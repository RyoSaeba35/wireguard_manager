# app/models/subscription.rb
class Subscription < ApplicationRecord
  belongs_to :user, optional: true  # Allow nil for future use
  belongs_to :plan

  has_many :devices, dependent: :destroy
  has_many :vpn_connections, through: :devices

  validates :name, :price, :plan, :expires_at, presence: true
  validates :name, uniqueness: true
  validates :price, numericality: { greater_than: 0 }
  validates :max_devices, numericality: { only_integer: true, greater_than: 0 }

  before_validation :set_plan_interval, on: :create

  # Scopes
  scope :active, -> {
    where(status: "active")
      .where("expires_at > ?", Time.current)
  }

  scope :expired, -> {
    where("expires_at < ?", Time.current)
  }

  scope :pending, -> { where(status: "pending") }
  scope :payment_pending, -> { where(status: "payment_pending") }

  # URL-friendly parameter
  def to_param
    name
  end

  def status
    db_status = self[:status]

    # Only override with 'expired' if it was an active subscription.
    # Terminal/pending statuses (payment_pending, failed, canceled) are never
    # overridden by expiry — they stay as-is regardless of expires_at.
    if db_status == "active" && expires_at.present? && expires_at < Time.current
      return 'expired'
    end

    db_status || 'active'
  end

  # Status predicate methods
  def active?
    status == "active" && expires_at > Time.current
  end

  def pending?
    status == "pending"
  end

  def payment_pending?
    status == "payment_pending"
  end

  def failed?
    status == "failed"
  end

  def expired?
    expires_at < Time.current
  end

  # Helper: current active devices
  def active_devices_count
    devices.where(active: true).count
  end

  def can_add_device?
    active_devices_count < max_devices
  end

  private

  def set_plan_interval
    self.plan_interval = plan.interval
  end
end
