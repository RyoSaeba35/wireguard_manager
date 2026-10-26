require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "whole euros are shown without decimals" do
    create_plan(interval: "month", price: 15)

    assert_equal "€15", starting_price(:en)
    assert_equal "€15", starting_price(:fr)
    assert_equal "15", starting_price_number
  end

  test "cents use a dot in English and a comma in French" do
    create_plan(interval: "month", price: 12.99)

    assert_equal "€12.99", starting_price(:en)
    assert_equal "€12,99", starting_price(:fr)
    assert_equal "12.99", starting_price_number
  end

  test "empty when there is no monthly plan" do
    assert_equal "", starting_price(:en)
    assert_nil starting_price_number
  end
end
