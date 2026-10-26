require "test_helper"

class PlanTest < ActiveSupport::TestCase
  test "starting price is the cheapest ACTIVE monthly plan" do
    create_plan(interval: "month", price: 19.99)
    create_plan(interval: "month", price: 12.50)
    create_plan(interval: "month", price: 5, active: false) # deactivated: ignored
    create_plan(interval: "week",  price: 4)                # not monthly: ignored
    create_plan(interval: "year",  price: 99)

    assert_equal BigDecimal("12.50"), Plan.starting_monthly_price
  end

  test "falls back to any monthly plan when none is active" do
    create_plan(interval: "month", price: 15, active: false)
    create_plan(interval: "year",  price: 99)

    assert_equal BigDecimal("15"), Plan.starting_monthly_price
  end

  test "is nil when there is no monthly plan at all" do
    create_plan(interval: "year", price: 99)

    assert_nil Plan.starting_monthly_price
  end
end
