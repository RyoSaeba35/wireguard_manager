# config/schedule.rb
set :output, "log/cron.log"
set :environment, ENV.fetch("RAILS_ENV", "development")
set :job_template, "PATH=/home/pierre/.rbenv/shims:/home/pierre/.rbenv/bin:/usr/local/bin:/usr/bin:/bin RAILS_ENV=:environment cd :path && /home/pierre/.rbenv/shims/bundle exec bin/rails runner ':job' >> :output 2>&1"

# Every 2 minutes — expire dead VPN sessions (app crashed without disconnect)
every 2.minutes do
  runner "HeartbeatMonitorJob.perform_now"
end

# Every minute — kill unauthorized sing-box connections via Clash API
every 1.minute do
  runner "ClashApiMonitorJob.perform_now"
end

# Every 15 minutes — revoke expired subscriptions
every 15.minutes do
  runner "RevokeExpiredSubscriptionsJob.perform_now"
end

# Every 30 minutes — reclaim abandoned payment sessions
every 30.minutes do
  runner "ExpireAbandonedSubscriptionsJob.perform_now"
end

# Daily at 3am — top up preallocated subscription pool
every :day, at: '3:00am' do
  runner "PreallocateSubscriptionsJob.perform_now"
end

# Daily at 2am — backup database to Wasabi
every :day, at: '2:00am' do
  runner "BackupDatabaseJob.perform_now"
end
