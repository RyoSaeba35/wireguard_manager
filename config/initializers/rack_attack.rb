# config/initializers/rack_attack.rb
#
# 🔐 Rate limiting for authentication endpoints.
# Rack::Attack inserts itself into the middleware stack automatically in Rails.
# Requests arrive through Cloudflare, so every throttle keys on ClientIp.for(req)
# (the visitor's real IP, see app/lib/client_ip.rb), never on req.ip, which is
# a rotating Cloudflare edge address.
#
# Counters live in Redis so every Heroku dyno shares them. We build a dedicated
# store (instead of relying on Rails.cache) with the same TLS settings as
# Sidekiq, because Heroku Redis uses a self-signed certificate: if the
# connection failed, Rack::Attack would silently never throttle anything.

if ENV["REDIS_URL"].present?
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV["REDIS_URL"],
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
    namespace: "rack_attack"
  )
end

class Rack::Attack
  # ------------------------------------------
  # Flutter API (api.vulcainvpn.com)
  # ------------------------------------------

  # Login: 10 attempts per minute per IP
  throttle("api/login/ip", limit: 10, period: 1.minute) do |req|
    ClientIp.for(req) if req.post? && req.path == "/api/login"
  end

  # Login: 30 attempts per hour per IP (stops slow, steady guessing)
  throttle("api/login/ip/hourly", limit: 30, period: 1.hour) do |req|
    ClientIp.for(req) if req.post? && req.path == "/api/login"
  end

  # Token refresh: generous, the app refreshes every ~30 min per device
  throttle("api/refresh/ip", limit: 30, period: 1.minute) do |req|
    ClientIp.for(req) if req.post? && req.path == "/api/refresh"
  end

  # Diagnostic reports send an email each time: keep them rare
  throttle("api/diagnostic/ip", limit: 5, period: 1.hour) do |req|
    ClientIp.for(req) if req.post? && req.path == "/api/diagnostic_report"
  end

  # ------------------------------------------
  # Website (Devise)
  # ------------------------------------------

  # Web login
  throttle("web/login/ip", limit: 10, period: 1.minute) do |req|
    ClientIp.for(req) if req.post? && req.path == "/users/sign_in"
  end

  # Password reset, confirmation and unlock emails (prevents email bombing)
  throttle("web/emails/ip", limit: 5, period: 15.minutes) do |req|
    if req.post? && ["/users/password", "/users/confirmation", "/users/unlock"].include?(req.path)
      ClientIp.for(req)
    end
  end

  # Sign-up
  throttle("web/signup/ip", limit: 5, period: 1.hour) do |req|
    ClientIp.for(req) if req.post? && req.path == "/users"
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
