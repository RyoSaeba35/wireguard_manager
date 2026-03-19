# app/models/device.rb
class Device < ApplicationRecord
  belongs_to :user
  belongs_to :subscription
  has_one :wireguard_client, -> { where(status: "active") }
  has_one :shadowsocks_client, -> { where(status: "active") }
  has_one :hysteria2_client, -> { where(status: "active") }

  before_create :generate_api_key

  private

  def generate_api_key
    self.api_key ||= SecureRandom.hex(32)
  end
end
