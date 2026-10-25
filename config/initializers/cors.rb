# config/initializers/cors.rb
#
# 🔐 CORS only matters for JavaScript running in a browser on ANOTHER site.
# The Flutter apps (Android, Windows, macOS, iOS) are not browsers and ignore
# CORS completely, and the website calls its own domain. So we only allow our
# own sites (in case the Flutter web build is ever served from them), instead
# of `origins '*'`, which let any website call the API from a visitor's browser.
allowed_origins = ["https://vulcainvpn.com", "https://www.vulcainvpn.com"]
allowed_origins << %r{\Ahttp://localhost(:\d+)?\z} unless Rails.env.production?

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*allowed_origins)

    resource "*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
