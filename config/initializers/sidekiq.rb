# config/initializers/sidekiq.rb
require 'sidekiq'
require 'sidekiq-scheduler'  # Force-load the scheduler

redis_url = ENV['REDIS_URL']

Sidekiq.configure_server do |config|
  config.redis = {
    url: redis_url,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }

  # Explicit scheduler setup
  config.on(:startup) do
    if defined?(Sidekiq::Scheduler)
      Sidekiq.schedule = YAML.load_file(Rails.root.join('config', 'sidekiq.yml'))
      Sidekiq::Scheduler.reload_schedule!
      Rails.logger.info("Sidekiq-Scheduler: Loaded schedule from config/sidekiq.yml")
    else
      Rails.logger.error("Sidekiq-Scheduler: Gem not loaded! Check bundle.")
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: redis_url,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }
end

