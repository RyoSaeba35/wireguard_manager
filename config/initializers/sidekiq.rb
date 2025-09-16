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
    schedule_file = "config/sidekiq.yml"

    if File.exist?(schedule_file)
      Sidekiq.schedule = YAML.load_file(schedule_file)
      Sidekiq::Scheduler.reload_schedule!
      Rails.logger.info "Sidekiq-Scheduler: Loaded schedule from #{schedule_file}"
      Rails.logger.info "Current schedule: #{Sidekiq.schedule.inspect}"
    else
      Rails.logger.error "Sidekiq-Scheduler: Could not find #{schedule_file}"
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: redis_url,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }
end
