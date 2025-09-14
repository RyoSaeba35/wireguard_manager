require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Code is not reloaded between requests.
  config.hosts << "fenguardvpn-5e34de44f30e.herokuapp.com"
  config.enable_reloading = false

  # Eager load code on boot.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Heroku requires the master key to be set via ENV.
  config.require_master_key = true

  # Heroku serves static files, but you can enable Rails to do so if needed.
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Compress JavaScript and CSS.
  config.assets.js_compressor  = :terser
  config.assets.css_compressor = :sass

  # Do not fall back to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Use Heroku's recommended logging.
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Log request IDs for tracing.
  config.log_tags = [:request_id]

  # Set log level (default: info).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use Heroku Redis for caching and Sidekiq.
  config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }

  # Use Sidekiq for background jobs.
  config.active_job.queue_adapter = :sidekiq

  # Configure Action Mailer for production (e.g., SendGrid, Mailgun, or Gmail).
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV['SMTP_ADDRESS'],
    port: ENV['SMTP_PORT'],
    domain: ENV['SMTP_DOMAIN'],
    user_name: ENV['SMTP_USERNAME'],
    password: ENV['SMTP_PASSWORD'],
    authentication: 'plain',
    enable_starttls_auto: true,
    openssl_verify_mode: 'none'
  }
  config.action_mailer.default_url_options = { host: ENV['APP_HOST'], protocol: 'https' }
  config.action_mailer.perform_caching = false

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Disable deprecation warnings in logs.
  config.active_support.report_deprecations = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Enable DNS rebinding protection.
  config.hosts = [
    ENV['APP_DOMAIN'],
    /.*\.#{ENV['APP_DOMAIN']}/ # Allow subdomains
  ]

  # Disable schema dump after migrations.
  config.active_record.dump_schema_after_migration = false

  # Force SSL (Heroku provides SSL by default).
  config.force_ssl = true

  # Use Heroku's database connection pooling.
  # config.active_record.database_selector = { delay: 2.seconds }
  # config.active_record.auto_explain_threshold_in_seconds = 0.5

  # Disable database selector context
  config.active_record.database_selector = nil
  config.active_record.database_resolver = nil
  config.active_record.database_resolver_context = nil

  # Store uploaded files (use S3 or another cloud storage in production).
  config.active_storage.service = :local # or :google, etc.
end
