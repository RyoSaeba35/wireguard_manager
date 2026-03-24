# app/models/refresh_token.rb
class RefreshToken < ApplicationRecord
  belongs_to :user

  validates :jti, presence: true, uniqueness: true
  validates :exp, presence: true

  # Clean up expired tokens (run this in a daily cron job)
  def self.cleanup_expired
    where('exp < ?', Time.current).delete_all
  end

  # Check if token is expired
  def expired?
    exp < Time.current
  end
end
