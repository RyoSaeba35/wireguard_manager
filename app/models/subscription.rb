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

  # Activates a paid subscription. Idempotent: the Stripe webhook and the
  # success-page check can both call it, only the first one does anything,
  # so the welcome email is sent exactly once.
  #
  # ✅ The paid period now starts at activation (payment), not when the
  # checkout page was opened. Before, a user who paid hours after opening
  # checkout lost those hours.
  def activate!
    activated = false
    with_lock do
      if self[:status] != "active"
        update!(status: "active", expires_at: self.class.expiry_from(plan&.interval))
        activated = true
      end
    end
    if activated && user.present?
      UserMailer.subscription_activated(user, self, invite_review: true).deliver_later
    end
    activated
  end

  # End of a paid period starting now. The 2 extra hours are the grace period
  # the checkout code already used.
  def self.expiry_from(interval, from: Time.current)
    period = case interval
             when "week"  then 1.week
             when "month" then 1.month
             when "year"  then 1.year
             else 1.month
             end
    from + period + 2.hours
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
