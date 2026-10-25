require "test_helper"

# Rack::Attack normally counts in Redis; here it gets an in-memory store
# for the duration of each test.
class Api::RateLimitingTest < ActionDispatch::IntegrationTest
  CLOUDFLARE_EDGES = %w[172.68.234.242 162.159.122.14 172.70.108.108].freeze

  setup do
    use_api_host!
    # Fixed clock: the 11 requests must land in the same one-minute window
    travel_to Time.zone.local(2026, 1, 1, 12, 0, 5)
    @original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset_vpn_exit_ips!
  end

  teardown do
    travel_back
    Rack::Attack.cache.store = @original_store
    Rack::Attack.reset_vpn_exit_ips!
  end

  def attempt_login(visitor_ip, edge: CLOUDFLARE_EDGES.sample)
    post "/api/login",
         params: { email: "nobody@example.com", password: "x" },
         headers: { "CF-Connecting-IP" => visitor_ip },
         env: { "REMOTE_ADDR" => edge },
         as: :json
    response.status
  end

  test "the 11th login in a minute from one visitor is throttled, whatever Cloudflare edge it uses" do
    codes = 11.times.map { |i| attempt_login("88.120.1.2", edge: CLOUDFLARE_EDGES[i % 3]) }

    assert_equal [401] * 10, codes.first(10)
    assert_equal 429, codes.last
    assert response.headers["Retry-After"].present?
  end

  test "one visitor being throttled does not affect another" do
    11.times { attempt_login("88.120.1.2") }
    assert_equal 401, attempt_login("91.170.4.5")
  end

  test "traffic coming through our own VPN server is not limited like a single visitor" do
    create_server(ip_address: "51.75.10.20")
    Rack::Attack.reset_vpn_exit_ips!

    codes = 25.times.map { attempt_login("51.75.10.20") }
    assert_not_includes codes, 429
  end

  test "a spoofed CF-Connecting-IP sent directly (not via Cloudflare) does not dodge the limit" do
    codes = 11.times.map do |i|
      post "/api/login",
           params: { email: "nobody@example.com", password: "x" },
           headers: { "CF-Connecting-IP" => "10.0.0.#{i}" }, # changes every time
           env: { "REMOTE_ADDR" => "203.0.113.50" },        # not a Cloudflare address
           as: :json
      response.status
    end
    assert_equal 429, codes.last
  end
end
