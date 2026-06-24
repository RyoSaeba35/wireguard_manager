# app/controllers/api/diagnostics_controller.rb
class Api::DiagnosticsController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!, raise: false
  before_action :authenticate_api_user!

  # POST api/diagnostic_report
  # Receives a diagnostic report from the Flutter app and emails it to support.
  # Authenticated with JWT so we know exactly which user sent it.
  def create
    user = @current_api_user

    device_info   = params[:device]          || 'Unknown'
    os_version    = params[:os_version]      || 'Unknown'
    app_version   = params[:app_version]     || 'Unknown'
    log_content   = params[:log]             || '(no log provided)'
    user_message  = params[:message]         || ''

    # Trim log to 100KB server-side as a safety net
    if log_content.bytesize > 100_000
      log_content = "[Log trimmed to 100KB server-side]\n\n" + log_content.last(100_000)
    end

    support_email = SystemSetting.instance.support_email.presence || 'support@vulcainvpn.com'

    DiagnosticMailer.report(
      to:           support_email,
      user_email:   user.email,
      user_id:      user.id,
      device_info:  device_info,
      os_version:   os_version,
      app_version:  app_version,
      user_message: user_message,
      log_content:  log_content,
      sent_at:      Time.current.iso8601
    ).deliver_later

    render json: { message: 'Diagnostic report sent successfully' }, status: :ok

  rescue => e
    Rails.logger.error "DiagnosticsController#create failed: #{e.message}"
    render json: { error: 'Failed to send report', message: e.message }, status: :internal_server_error
  end

  private

  def authenticate_api_user!
    token = request.headers['Authorization']&.split(' ')&.last

    unless token.present?
      render json: { error: 'Authorization token required' }, status: :unauthorized
      return
    end

    begin
      payload = JWT.decode(
        token,
        ENV['DEVISE_JWT_SECRET_KEY'],
        true,
        algorithm: 'HS256'
      ).first

      if JwtDenylist.exists?(jti: payload['jti'])
        render json: { error: 'Token has been revoked' }, status: :unauthorized
        return
      end

      @current_api_user = User.find(payload['sub'])

    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render json: { error: 'Invalid or expired token' }, status: :unauthorized
    end
  end
end
