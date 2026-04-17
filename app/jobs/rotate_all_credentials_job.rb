# app/jobs/rotate_all_credentials_job.rb
class RotateAllCredentialsJob < ApplicationJob
  queue_as :default

  def perform
    Server.active.healthy.find_each do |server|
      rotate_server_credentials(server)
    end
  end

  private

  def rotate_server_credentials(server)
    Rails.logger.info "Rotating credentials for #{server.name}"

    service = VpnConfigSetService.new(server)
    count = service.rotate_all_credentials

    Rails.logger.info "✅ Rotated #{count} credentials for #{server.name}"
  rescue => e
    Rails.logger.error "Failed to rotate credentials for #{server.name}: #{e.message}"
    # Don't raise - continue with other servers
  end
end
