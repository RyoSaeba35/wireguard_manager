class WireguardClient < ApplicationRecord
  # Association with User
  belongs_to :subscription

  validates :name, uniqueness: true

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
end
