class Hysteria2Client < ApplicationRecord
  encrypts :password

  belongs_to :subscription
  belongs_to :device, optional: true

  validates :name, presence: true, uniqueness: true
  validates :password, presence: true

  scope :preallocated, -> { where(status: "preallocated") }
  scope :active, -> { where(status: "active") }
end
