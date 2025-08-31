# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever
# config/schedule.rb

# every :day, at: '12:00 am' do
#   runner "RevokeExpiredSubscriptionsJob.perform_now"
# end

set :output, "log/cron.log"
set :environment, 'development'
set :job_template, "PATH=/home/pierre/.rbenv/shims:/home/pierre/.rbenv/bin:/usr/local/bin:/usr/bin:/bin RAILS_ENV=development cd :path && /home/pierre/.rbenv/shims/ruby -r dotenv/load :path/bin/bundle exec bin/rails runner ':job' >> :output 2>&1"

every :hour do
  runner "RevokeExpiredSubscriptionsJob.perform_now"
end
