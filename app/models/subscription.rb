# app/models/subscription.rb
class Subscription < ApplicationRecord
  belongs_to :user, optional: true  # Allow nil for future use
  belongs_to :plan

  # NEW: No server association (pooling!)
  # REMOVED: belongs_to :server

  # NEW: Keep devices
  has_many :devices, dependent: :destroy

  # NEW: Connections through devices
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

  # REMOVED: preallocated scope (no more preallocated subscriptions)

  # URL-friendly parameter
  def to_param
    name
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
