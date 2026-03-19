# app/models/shadowsocks_client.rb
class ShadowsocksClient < ApplicationRecord
  encrypts :password

  belongs_to :subscription
  belongs_to :device, optional: true

  validates :name, presence: true, uniqueness: true
  validates :password, presence: true

  scope :preallocated, -> { where(status: "preallocated") }
  scope :active, -> { where(status: "active") }
end
