# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  CLIENTS_PER_SUBSCRIPTION = 3

  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError
end
