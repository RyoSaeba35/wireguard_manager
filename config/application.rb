require_relative "boot"
require "rails/all"
Bundler.require(*Rails.groups)

module WireguardManager
  class Application < Rails::Application
    config.load_defaults 7.2
    config.autoload_lib(ignore: %w[assets tasks])
    config.autoload_paths += %W(#{config.root}/app/services)

    # Use environment variables in production, fall back to credentials in development
    config.active_record.encryption.primary_key =
      ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'] || Rails.application.credentials.secret_key_base
    config.active_record.encryption.deterministic_key =
      ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY'] || Rails.application.credentials.secret_key_base
    config.active_record.encryption.key_derivation_salt =
      ENV['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT'] || Rails.application.credentials.secret_key_base
  end
end
