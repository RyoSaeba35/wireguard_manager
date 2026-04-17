# app/jobs/recycle_configs_job.rb
class RecycleConfigsJob < ApplicationJob
  queue_as :default

  def perform
    Server.active.healthy.find_each do |server|
      recycle_server_configs(server)
    end
  end

  private

  def recycle_server_configs(server)
    service = VpnConfigSetService.new(server)
    count = service.recycle_stale_configs

    Rails.logger.info "Recycled #{count} stale configs for #{server.name}" if count > 0
  rescue => e
    Rails.logger.error "Failed to recycle configs for #{server.name}: #{e.message}"
  end
end
