class WireguardClient < ApplicationRecord
  # Association with User
  belongs_to :user
  has_one :subscription, dependent: :destroy

  def expired?
    expires_at.present? && expires_at < Time.current
  end
end
