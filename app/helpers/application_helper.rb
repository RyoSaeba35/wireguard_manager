module ApplicationHelper
  # "€15" or "€12.99" (English) / "€12,99" (French): the cheapest monthly plan
  # price, formatted like the rest of the site. Blog articles contain both
  # languages on one page, so the language is passed explicitly.
  # Returns "" if there is no monthly plan at all.
  def starting_price(lang = :en)
    amount = starting_monthly_amount
    return "" unless amount

    number = amount.frac.zero? ? amount.to_i.to_s : format("%.2f", amount)
    number = number.tr(".", ",") if lang.to_s == "fr"
    "€#{number}"
  end

  # Plain number for Google's structured data: "15" or "12.99"; nil if none.
  def starting_price_number
    amount = starting_monthly_amount
    return nil unless amount

    amount.frac.zero? ? amount.to_i.to_s : format("%.2f", amount)
  end

  private

  # One query per page, however many times the price appears
  def starting_monthly_amount
    return @starting_monthly_amount if defined?(@starting_monthly_amount)

    @starting_monthly_amount = Plan.starting_monthly_price&.to_d
  end
end
