# app/lib/client_ip.rb
#
# Real client IP behind Cloudflare -> Heroku router -> Rails.
#
# Without this, request.ip / request.remote_ip return a Cloudflare edge address
# (162.158.x, 172.68.x, ...) that changes from one request to the next. That
# broke rate limiting (each edge IP got its own counter) and stored Cloudflare
# addresses in devices.last_connection_ip.
#
# Cloudflare puts the visitor's address in the CF-Connecting-IP header. We only
# trust it when the request really arrived from a Cloudflare address; otherwise
# anyone calling the *.herokuapp.com URL directly could send a fake header.
#
# Ranges from https://www.cloudflare.com/ips/ (checked 2026-10-25).
# Cloudflare changes them rarely; re-check once a year.
require "ipaddr"

module ClientIp
  CLOUDFLARE_RANGES = %w[
    173.245.48.0/20
    103.21.244.0/22
    103.22.200.0/22
    103.31.4.0/22
    141.101.64.0/18
    108.162.192.0/18
    190.93.240.0/20
    188.114.96.0/20
    197.234.240.0/22
    198.41.128.0/17
    162.158.0.0/15
    104.16.0.0/13
    104.24.0.0/14
    172.64.0.0/13
    131.0.72.0/22
    2400:cb00::/32
    2606:4700::/32
    2803:f800::/32
    2405:b500::/32
    2405:8100::/32
    2a06:98c0::/29
    2c0f:f248::/32
  ].map { |range| IPAddr.new(range) }.freeze

  # Works with both Rack::Request (Rack::Attack) and ActionDispatch::Request (controllers)
  def self.for(request)
    peer = request.ip.to_s

    if cloudflare?(peer)
      cf_ip = request.get_header("HTTP_CF_CONNECTING_IP").to_s.strip
      return normalize(cf_ip) if valid_ip?(cf_ip)
    end

    normalize(peer)
  end

  def self.cloudflare?(ip)
    addr = IPAddr.new(ip)
    CLOUDFLARE_RANGES.any? { |range| range.family == addr.family && range.include?(addr) }
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    false
  end

  def self.valid_ip?(ip)
    return false if ip.empty?
    IPAddr.new(ip)
    true
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    false
  end

  # "::ffff:1.2.3.4" -> "1.2.3.4"
  def self.normalize(ip)
    ip.sub(/\A::ffff:/i, "")
  end
end
