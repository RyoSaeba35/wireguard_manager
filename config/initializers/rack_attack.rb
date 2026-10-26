# config/initializers/rack_attack.rb
#
# 🔐 Rate limiting for authentication endpoints.
# Rack::Attack inserts itself into the middleware stack automatically in Rails.
# Requests arrive through Cloudflare, so every throttle keys on ClientIp.for(req)
# (the visitor's real IP, see app/lib/client_ip.rb), never on req.ip, which is
# a rotating Cloudflare edge address.
#
# VPN exit IPs: the app does not exclude itself from the tunnel, so while a
# user is connected, their API calls (token refresh, diagnostics, re-login)
# reach us from the VPN SERVER's IP. All connected users share that address,
# so the normal per-IP limits would block everyone at once (e.g. /api/refresh
# at ~900 connected devices per server). Requests from our own servers get
# separate, much higher limits instead. Accounts stay protected by Devise
# :lockable (5 failed attempts per account) either way.
#
# Counters live in Redis so every Heroku dyno shares them. We build a dedicated
# store (instead of relying on Rails.cache) with the same TLS settings as
# Sidekiq, because Heroku Redis uses a self-signed certificate: if the
# connection failed, Rack::Attack would silently never throttle anything.

# (Tests use the in-memory/null store instead; see test/integration/api/rate_limiting_test.rb)
if ENV["REDIS_URL"].present? && !Rails.env.test?
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV["REDIS_URL"],
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
    namespace: "rack_attack"
  )
end

class Rack::Attack
  # ------------------------------------------
  # VPN server IPs (refreshed every 5 minutes, per process)
  # ------------------------------------------
  VPN_EXIT_IPS_TTL = 5 * 60
  @vpn_exit_ips = Set.new
  @vpn_exit_ips_loaded_at = nil
  @vpn_exit_ips_mutex = Mutex.new

  def self.vpn_exit_ips
    @vpn_exit_ips_mutex.synchronize do
      if @vpn_exit_ips_loaded_at.nil? || Time.now.to_i - @vpn_exit_ips_loaded_at > VPN_EXIT_IPS_TTL
        @vpn_exit_ips = Server.pluck(:ip_address).compact.map { |ip| ip.to_s.strip }.to_set
        @vpn_exit_ips_loaded_at = Time.now.to_i
      end
      @vpn_exit_ips
    end
  rescue StandardError => e
    # Never break requests because of this lookup; keep the last known list
    Rails.logger.error "[Rack::Attack] Could not load VPN server IPs: #{e.message}"
    @vpn_exit_ips
  end

  # Forget the cached list (tests, or right after adding a server in the console)
  def self.reset_vpn_exit_ips!
    @vpn_exit_ips_mutex.synchronize { @vpn_exit_ips_loaded_at = nil }
  end

  def self.vpn_exit?(ip)
    vpn_exit_ips.include?(ip)
  end

  # Real client IP, unless it is one of our VPN servers (then nil = not counted)
  def self.public_ip(req)
    ip = ClientIp.for(req)
    vpn_exit?(ip) ? nil : ip
  end

  # Our VPN server IP if the request came through the tunnel, else nil
  def self.vpn_exit_ip(req)
    ip = ClientIp.for(req)
    vpn_exit?(ip) ? ip : nil
  end

  # ------------------------------------------
  # Flutter API (api.vulcainvpn.com), normal internet users
  # ------------------------------------------

  # Login: 10 attempts per minute per IP
  throttle("api/login/ip", limit: 10, period: 1.minute) do |req|
    public_ip(req) if req.post? && req.path == "/api/login"
  end

  # Login: 30 attempts per hour per IP (stops slow, steady guessing)
  throttle("api/login/ip/hourly", limit: 30, period: 1.hour) do |req|
    public_ip(req) if req.post? && req.path == "/api/login"
  end

  # Token refresh: generous, the app refreshes every ~30 min per device
  throttle("api/refresh/ip", limit: 30, period: 1.minute) do |req|
    public_ip(req) if req.post? && req.path == "/api/refresh"
  end

  # Diagnostic reports send an email each time: keep them rare
  throttle("api/diagnostic/ip", limit: 5, period: 1.hour) do |req|
    public_ip(req) if req.post? && req.path == "/api/diagnostic_report"
  end

  # Sign-up from the app (same limit as the website sign-up)
  throttle("api/signup/ip", limit: 5, period: 1.hour) do |req|
    public_ip(req) if req.post? && req.path == "/api/signup"
  end

  # Password reset and confirmation emails (prevents email bombing)
  throttle("api/emails/ip", limit: 5, period: 15.minutes) do |req|
    if req.post? && ["/api/password/reset", "/api/confirmation/resend"].include?(req.path)
      public_ip(req)
    end
  end

  # Email confirmation from the app (token guessing)
  throttle("api/confirm/ip", limit: 10, period: 15.minutes) do |req|
    public_ip(req) if req.post? && req.path == "/api/confirmation"
  end

  # Account deletion asks for the password: cap guessing
  throttle("api/account_delete/ip", limit: 5, period: 15.minutes) do |req|
    public_ip(req) if req.delete? && req.path == "/api/account"
  end

  # ------------------------------------------
  # Flutter API, requests coming through our own VPN servers
  # (one counter per server, shared by every connected user)
  # ------------------------------------------

  # Re-logins from connected users. Brute force through the VPN is still
  # capped per account by Devise :lockable.
  throttle("api/login/vpn", limit: 200, period: 1.minute) do |req|
    vpn_exit_ip(req) if req.post? && req.path == "/api/login"
  end

  # 3,000 devices per server refreshing every ~30 min is ~100/min on average.
  # 1,000/min leaves room for bursts (e.g. everyone reconnecting after an outage).
  throttle("api/refresh/vpn", limit: 1_000, period: 1.minute) do |req|
    vpn_exit_ip(req) if req.post? && req.path == "/api/refresh"
  end

  # Each report is an email: cap the total per server
  throttle("api/diagnostic/vpn", limit: 60, period: 1.hour) do |req|
    vpn_exit_ip(req) if req.post? && req.path == "/api/diagnostic_report"
  end

  throttle("api/signup/vpn", limit: 60, period: 1.hour) do |req|
    vpn_exit_ip(req) if req.post? && req.path == "/api/signup"
  end

  throttle("api/emails/vpn", limit: 60, period: 15.minutes) do |req|
    if req.post? && ["/api/password/reset", "/api/confirmation/resend"].include?(req.path)
      vpn_exit_ip(req)
    end
  end

  throttle("api/confirm/vpn", limit: 100, period: 15.minutes) do |req|
    vpn_exit_ip(req) if req.post? && req.path == "/api/confirmation"
  end

  throttle("api/account_delete/vpn", limit: 60, period: 15.minutes) do |req|
    vpn_exit_ip(req) if req.delete? && req.path == "/api/account"
  end

  # ------------------------------------------
  # Website (Devise)
  # ------------------------------------------

  # Web login
  throttle("web/login/ip", limit: 10, period: 1.minute) do |req|
    public_ip(req) if req.post? && req.path == "/users/sign_in"
  end

  # Password reset, confirmation and unlock emails (prevents email bombing)
  throttle("web/emails/ip", limit: 5, period: 15.minutes) do |req|
    if req.post? && ["/users/password", "/users/confirmation", "/users/unlock"].include?(req.path)
      public_ip(req)
    end
  end

  # Sign-up
  throttle("web/signup/ip", limit: 5, period: 1.hour) do |req|
    public_ip(req) if req.post? && req.path == "/users"
  end

  # Website through the VPN: same endpoints, higher shared limits
  throttle("web/login/vpn", limit: 200, period: 1.minute) do |req|
    vpn_exit_ip(req) if req.post? && req.path == "/users/sign_in"
  end

  throttle("web/emails/vpn", limit: 60, period: 15.minutes) do |req|
    if req.post? && ["/users/password", "/users/confirmation", "/users/unlock"].include?(req.path)
      vpn_exit_ip(req)
    end
  end

  throttle("web/signup/vpn", limit: 60, period: 1.hour) do |req|
    vpn_exit_ip(req) if req.post? && req.path == "/users"
  end

  # ------------------------------------------
  # Response when throttled
  # ------------------------------------------
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"] || {}
    retry_after = (match_data[:period] || 60).to_i

    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ error: "Too many attempts. Please wait a moment and try again." }.to_json]
    ]
  end
end

# Log throttled requests so you can see abuse in Heroku logs
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn "[Rack::Attack] Throttled #{req.env['rack.attack.matched']} " \
                    "ip=#{ClientIp.for(req)} path=#{req.path}"
end
