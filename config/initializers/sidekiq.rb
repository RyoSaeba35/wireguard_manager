# config/initializers/sidekiq.rb
require 'sidekiq'
require 'sidekiq/scheduler'

redis_url = ENV['REDIS_URL']

Sidekiq.configure_server do |config|
  config.redis = {
    url: redis_url,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }

  # Explicit scheduler setup
  config.on(:startup) do
    schedule_file = Rails.root.join('config', 'sidekiq.yml')

    if File.exist?(schedule_file)
      loaded_schedule = YAML.load_file(schedule_file)
      if loaded_schedule.key?(:scheduled)
        Sidekiq.schedule = loaded_schedule[:scheduled]
        Sidekiq::Scheduler.reload_schedule!
        Rails.logger.info "Sidekiq-Scheduler: Loaded schedule: #{Sidekiq.schedule.inspect}"
      else
        Rails.logger.error "Sidekiq-Scheduler: No :scheduled key found in YAML"
      end
    else
      Rails.logger.error "Sidekiq-Scheduler: YAML file not found at #{schedule_file}"
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: redis_url,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }
end
