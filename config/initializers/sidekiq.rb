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
      {
        # Every 2 minutes — expire dead VPN sessions
        # 'heartbeat_monitor' => {
        #   'cron'  => '*/2 * * * *',
        #   'class' => 'HeartbeatMonitorJob',
        #   'queue' => 'default'
        # },
        # Every minute — kill unauthorized sing-box connections
        'clash_api_monitor' => {
          'cron'  => '* * * * *',
          'class' => 'ClashApiMonitorJob',
          'queue' => 'default'
        },
        # Every 15 minutes — revoke expired subscriptions
        'revoke_expired_subscriptions' => {
          'cron'  => '*/15 * * * *',
          'class' => 'RevokeExpiredSubscriptionsJob',
          'queue' => 'default'
        },
        # Every 30 minutes — reclaim abandoned payment sessions
        'expire_abandoned_subscriptions' => {
          'cron'  => '*/30 * * * *',
          'class' => 'ExpireAbandonedSubscriptionsJob',
          'queue' => 'default'
        },
        # Daily at 3am — top up preallocated subscription pool
        'preallocate_subscriptions' => {
          'cron'  => '0 3 * * *',
          'class' => 'PreallocateSubscriptionsJob',
          'queue' => 'default'
        },
        # Daily at 4am — clean up expired tokens
        'cleanup_expired_tokens' => {
          'cron'  => '0 4 * * *',
          'class' => 'CleanupExpiredTokensJob',
          'queue' => 'default'
        },
        # Daily at 2am — backup database to Wasabi
        'backup_database' => {
          'cron'  => '0 2 * * *',
          'class' => 'BackupDatabaseJob',
          'queue' => 'default'
        }
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
