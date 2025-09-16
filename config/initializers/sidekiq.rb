# config/initializers/sidekiq.rb
require 'sidekiq'
require 'sidekiq-cron'

redis_url = ENV['REDIS_URL']

Sidekiq.configure_server do |config|
  config.redis = {
    url: redis_url,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }

  config.on(:startup) do
    Sidekiq::Cron::Job.load_from_hash(
      'revoke_expired_subscriptions' => {
        'cron'  => '0 */6 * * *',  # Every 6 hours
        'class' => 'RevokeExpiredSubscriptionsJob',
        'queue' => 'default'
      }
    )
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: redis_url,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }
end
