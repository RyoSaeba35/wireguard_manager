class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :plan
  belongs_to :server
  has_many :wireguard_clients, dependent: :destroy
  validates :name, :price, :plan, :expires_at, presence: true
  validates :name, uniqueness: { scope: :user_id } # Ensure names are unique per user
  validates :price, numericality: { greater_than: 0 }
  before_validation :set_plan_interval, on: :create

  # Scope to find active subscriptions
  scope :active, -> {
    where(status: "active")
      .where("expires_at > ?", Time.current)
  }

  # Scope to find expired subscriptions
  scope :expired, -> {
    where("expires_at < ?", Time.current)
  }

  # Scope to find pending subscriptions
  scope :pending, -> {
    where(status: "pending")
  }

  # Use name in URLs instead of ID
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

  def failed?
    status == "failed"
  end

  def expired?
    expires_at < Time.current
  end

  def set_plan_interval
    self.plan_interval = plan.interval
  end
end
