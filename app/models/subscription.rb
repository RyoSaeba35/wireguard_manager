class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :wireguard_client

  # Scope to find active subscriptions
  scope :active, -> {
    where(status: "active")
      .where("expires_at > ?", Time.current)
  }

  # Scope to find expired subscriptions
  scope :expired, -> {
    where("expires_at < ?", Time.current)
  }

  def active?
    status == "active" && expires_at > Time.current
  end
end
