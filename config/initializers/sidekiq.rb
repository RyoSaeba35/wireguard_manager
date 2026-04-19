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
        # ==========================================
        # MONITORING & HEALTH CHECKS
        # ==========================================

        # Every 2 minutes — check server health (ping /api/server-status)
        'server_health_check' => {
          'cron'  => '*/2 * * * *',
          'class' => 'ServerHealthCheckJob',
          'queue' => 'default'
        },

        # Every minute — monitor sing-box connections and kill unauthorized
        'clash_api_monitor' => {
          'cron'  => '* * * * *',
          'class' => 'ClashApiMonitorJob',
          'queue' => 'default'
        },

        # ==========================================
        # SUBSCRIPTION MANAGEMENT
        # ==========================================

        # Every 15 minutes — revoke expired subscriptions
        'revoke_expired_subscriptions' => {
          'cron'  => '*/15 * * * *',
          'class' => 'RevokeExpiredSubscriptionsJob',
          'queue' => 'default'
        },

        # Every 30 minutes — expire abandoned payment sessions
        'expire_abandoned_subscriptions' => {
          'cron'  => '*/30 * * * *',
          'class' => 'ExpireAbandonedSubscriptionsJob',
          'queue' => 'default'
        },

        # ==========================================
        # POOLING MAINTENANCE
        # ==========================================

        # Every 2 hours — recycle stale config sets
        'recycle_configs' => {
          'cron'  => '0 */2 * * *',
          'class' => 'RecycleConfigsJob',
          'queue' => 'default'
        },

        # Daily at 3 AM — rotate all credentials (security)
        # 'rotate_all_credentials' => {
        #   'cron'  => '0 3 * * *',
        #   'class' => 'RotateAllCredentialsJob',
        #   'queue' => 'default'
        # },

        # ==========================================
        # CLEANUP & BACKUP
        # ==========================================

        # Daily at 4 AM — clean up expired tokens
        'cleanup_expired_tokens' => {
          'cron'  => '0 4 * * *',
          'class' => 'CleanupExpiredTokensJob',
          'queue' => 'default'
        },

        # Daily at 2 AM — backup database to Wasabi
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
