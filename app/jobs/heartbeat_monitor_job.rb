# app/jobs/heartbeat_monitor_job.rb
class HeartbeatMonitorJob < ApplicationJob
  queue_as :default

  # Expire sessions where app crashed or lost connection
  # Runs every 2 minutes via sidekiq-cron
  HEARTBEAT_TIMEOUT = 3.minutes

  def perform
    expired_count = 0

    Device.where(active: true)
          .where("last_heartbeat_at < ?", HEARTBEAT_TIMEOUT.ago)
          .find_each do |device|
      device.update!(
        active: false,
        connected_at: nil
      )
      expired_count += 1
      Rails.logger.info "Expired dead session for device #{device.device_id}"
    end

    Rails.logger.info "HeartbeatMonitorJob: expired #{expired_count} dead sessions"
  end
end
