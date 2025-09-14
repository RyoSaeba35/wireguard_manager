set :output, "log/cron.log"
set :environment, 'development'
set :job_template, "PATH=/home/pierre/.rbenv/shims:/home/pierre/.rbenv/bin:/usr/local/bin:/usr/bin:/bin RAILS_ENV=development cd :path && /home/pierre/.rbenv/shims/bundle exec bin/rails runner ':job' >> :output 2>&1"

every :hour do
  runner "RevokeExpiredSubscriptionsJob.perform_now"
end
