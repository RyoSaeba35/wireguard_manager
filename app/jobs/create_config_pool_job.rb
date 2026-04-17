# app/jobs/create_config_pool_job.rb
class CreateConfigPoolJob < ApplicationJob
  queue_as :default

  def perform(server_id, pool_size = nil)
    server = Server.find(server_id)
    pool_size ||= server.config_pool_size

    Rails.logger.info "Creating config pool for #{server.name} (#{pool_size} configs)"

    service = VpnConfigSetService.new(server)
    service.create_pool(pool_size)

    Rails.logger.info "✅ Created pool for #{server.name}"
  rescue => e
    Rails.logger.error "Failed to create pool for server #{server_id}: #{e.message}"
    raise
  end
end
