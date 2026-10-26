# app/models/plan.rb
class Plan < ApplicationRecord
  has_many :subscriptions, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :interval, presence: true, inclusion: { in: %w[week month year] }
  validates :active, inclusion: { in: [true, false] }
  # validates :stripe_price_id, presence: true

  scope :active, -> { where(active: true) }

  # Price used in "from €X/month" texts across the site (meta descriptions,
  # Google structured data, blog articles). Change a plan's price in the admin
  # panel and every one of those texts follows.
  #
  # Cheapest ACTIVE monthly plan; if none is active (e.g. while you swap
  # plans), the cheapest monthly plan at all; nil only if no monthly plan exists.
  def self.starting_monthly_price
    where(interval: "month").active.minimum(:price) ||
      where(interval: "month").minimum(:price)
  end

  def localized_name
    I18n.locale == :fr && name_fr.present? ? name_fr : name
  end

  def localized_description
    I18n.locale == :fr && description_fr.present? ? description_fr : description
  end
end
