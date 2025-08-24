class WireguardClient < ApplicationRecord
  # Association with User
  belongs_to :user
end
