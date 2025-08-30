class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :wireguard_client

  def active?
    status == "active" && expires_at > Time.current
  end
end
