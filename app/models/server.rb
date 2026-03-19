# app/models/server.rb
class Server < ApplicationRecord
  encrypts :ssh_user, :ssh_password, :ssh_private_key, deterministic: true
  encrypts :singbox_ss_master_password, :singbox_salamander_password

  has_many :subscriptions
  has_many :shadowsocks_clients, through: :subscriptions
  has_many :hysteria2_clients, through: :subscriptions

  validates :name, presence: true
  validates :ip_address, presence: true
  validates :max_subscriptions, numericality: { only_integer: true, greater_than: 0 }

  validate :current_subscriptions_cannot_be_negative

  def current_subscriptions_cannot_be_negative
    if current_subscriptions < 0
      errors.add(:current_subscriptions, "cannot be negative")
      throw :abort
    end
  end

  # validate :ssh_credentials_present, if: :active?

  # def ssh_credentials_present
  #   if ssh_user.blank? || ssh_password.blank?
  #     errors.add(:base, "SSH credentials are required for active servers")
  #   end
  # end
end
