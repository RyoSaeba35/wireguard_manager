# app/jobs/server_health_check_job.rb
require 'net/http'

class ServerHealthCheckJob < ApplicationJob
  queue_as :default

  HEALTH_ENDPOINT = "/api/server-status"
  MAX_FAILURES = 3

  def perform
    Server.active.find_each do |server|
      check_server_health(server)
    end
  end

  private

  def check_server_health(server)
    begin
      uri = URI.parse("http://#{server.ip_address}#{HEALTH_ENDPOINT}")
      request = Net::HTTP::Get.new(uri)
      request.basic_auth('vulcainadmin', 'Vulcain1989!')

      response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) do |http|
        http.request(request)
      end

      if response.code == "200"
        data = JSON.parse(response.body)
        status = data['status']

        if status == "OK" || status == "WARNING"
          # Server is healthy
          if !server.healthy?
            Rails.logger.info "✅ Server #{server.name} is now healthy"
            AdminMailer.server_recovered(server).deliver_later
          end

          server.update!(
            healthy: true,
            last_health_check: Time.current,
            health_failures: 0
          )
        else
          # Server returned error status
          mark_unhealthy(server, "Status: #{status}")
        end
      else
        # HTTP error
        mark_unhealthy(server, "HTTP #{response.code}")
      end

    rescue StandardError => e
      # Connection failed
      mark_unhealthy(server, e.message)
    end
  end

  def mark_unhealthy(server, reason)
    failures = server.health_failures + 1

    server.update!(
      last_health_check: Time.current,
      health_failures: failures
    )

    if failures >= MAX_FAILURES && server.healthy?
      # Mark as unhealthy after 3 consecutive failures
      server.update!(healthy: false)

      Rails.logger.error "🚨 Server #{server.name} marked unhealthy after #{failures} failures: #{reason}"
      AdminMailer.server_down_alert(server, reason).deliver_now
    else
      Rails.logger.warn "⚠️ Server #{server.name} health check failed (#{failures}/#{MAX_FAILURES}): #{reason}"
    end
  end
end
