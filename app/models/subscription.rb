class Subscription < ApplicationRecord
  belongs_to :user, optional: true  # Allow user_id to be nil
  belongs_to :plan
  belongs_to :server
  has_many :wireguard_clients, dependent: :destroy

  validates :name, :price, :plan, :expires_at, presence: true
  validates :name, uniqueness: true  # Globally unique names
  validates :price, numericality: { greater_than: 0 }

  before_validation :set_plan_interval, on: :create

  # Scopes
  scope :active, -> {
    where(status: "active")
      .where("expires_at > ?", Time.current)
  }

  scope :expired, -> {
    where("expires_at < ?", Time.current)
  }

  scope :pending, -> {
    where(status: "pending")
  }

  scope :preallocated, -> {
    where(user_id: nil, status: "preallocated")
  }

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

  def failed?
    status == "failed"
  end

  def expired?
    expires_at < Time.current
  end

  def preallocated?
    status == "preallocated"
  end

  def set_plan_interval
    self.plan_interval = plan.interval
  end
end
