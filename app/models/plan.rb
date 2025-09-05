# app/models/plan.rb
class Plan < ApplicationRecord
  has_many :subscriptions, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :interval, presence: true, inclusion: { in: %w[week month year] }
  validates :active, inclusion: { in: [true, false] }

  scope :active, -> { where(active: true) }
end
