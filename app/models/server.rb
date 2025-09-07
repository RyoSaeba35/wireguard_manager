# app/models/server.rb
class Server < ApplicationRecord
  encrypts :ssh_user, :ssh_password, deterministic: true
  has_many :subscriptions

  validates :name, presence: true
  validates :ip_address, presence: true
  validates :max_subscriptions, numericality: { only_integer: true, greater_than: 0 }

  # validate :ssh_credentials_present, if: :active?

  # def ssh_credentials_present
  #   if ssh_user.blank? || ssh_password.blank?
  #     errors.add(:base, "SSH credentials are required for active servers")
  #   end
  # end
end
