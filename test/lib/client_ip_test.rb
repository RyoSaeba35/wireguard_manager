require "test_helper"

class ClientIpTest < ActiveSupport::TestCase
  def request_from(remote_addr, cf_connecting_ip: nil)
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => remote_addr)
    env["HTTP_CF_CONNECTING_IP"] = cf_connecting_ip if cf_connecting_ip
    Rack::Request.new(env)
  end

  test "uses CF-Connecting-IP when the request comes from a Cloudflare edge" do
    assert_equal "88.120.1.2", ClientIp.for(request_from("172.68.234.242", cf_connecting_ip: "88.120.1.2"))
    assert_equal "88.120.1.2", ClientIp.for(request_from("162.159.122.14", cf_connecting_ip: "88.120.1.2"))
  end

  test "supports IPv6 edges and visitors" do
    assert_equal "2a01:cb00::1", ClientIp.for(request_from("2a06:98c0:3600::103", cf_connecting_ip: "2a01:cb00::1"))
  end

  test "ignores a spoofed CF-Connecting-IP when the caller is not Cloudflare" do
    assert_equal "203.0.113.9", ClientIp.for(request_from("203.0.113.9", cf_connecting_ip: "1.1.1.1"))
  end

  test "falls back to the peer address when the header is missing or invalid" do
    assert_equal "172.70.108.108", ClientIp.for(request_from("172.70.108.108"))
    assert_equal "172.70.108.108", ClientIp.for(request_from("172.70.108.108", cf_connecting_ip: "not-an-ip"))
  end

  test "strips the IPv4-mapped IPv6 prefix" do
    assert_equal "203.0.113.9", ClientIp.for(request_from("::ffff:203.0.113.9"))
  end
end
