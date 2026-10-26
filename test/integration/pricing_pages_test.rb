require "test_helper"

# The "from €X/month" texts follow the price set in the admin panel.
class PricingPagesTest < ActionDispatch::IntegrationTest
  setup do
    @monthly = create_plan(interval: "month", price: 12.99)
  end

  test "home page: meta description and Google structured data use the plan price" do
    get "/"
    assert_response :ok
    assert_includes response.body, "From €12.99/month."
    assert_includes response.body, '"price": "12.99"'
    assert_not_includes response.body, "€15"
  end

  # Blog pages show one language at a time: French by default, English with ?locale=en
  test "blog article in French uses the plan price, French style" do
    get "/blog/proteger-connexion-en-voyage"
    assert_response :ok
    assert_includes response.body, "€12,99/mois"
    assert_not_includes response.body, "€15"
  end

  test "blog article in English uses the plan price, English style" do
    get "/blog/proteger-connexion-en-voyage", params: { locale: "en" }
    assert_response :ok
    assert_includes response.body, "€12.99/month"
    assert_not_includes response.body, "€15"
  end

  test "changing the price in the admin panel changes the texts" do
    @monthly.update!(price: 9)

    get "/blog/vpn-vs-nordvpn-expressvpn"
    assert_includes response.body, "€9/mois"

    get "/blog/vpn-vs-nordvpn-expressvpn", params: { locale: "en" }
    assert_includes response.body, "€9/month"
  end

  test "Google structured data stays valid JSON" do
    get "/"
    blocks = response.body.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten
    app_data = blocks.filter_map { |b| JSON.parse(b) rescue nil }.find { |d| d["offers"] }

    assert app_data, "no structured data block with offers found"
    assert_equal "12.99", app_data.dig("offers", "price")
  end
end
