# app/mailers/diagnostic_mailer.rb
class DiagnosticMailer < ApplicationMailer
  default from: 'noreply@vulcainvpn.com'

  def report(to:, user_email:, user_id:, device_info:, os_version:,
             app_version:, user_message:, log_content:, sent_at:)
    @user_email   = user_email
    @user_id      = user_id
    @device_info  = device_info
    @os_version   = os_version
    @app_version  = app_version
    @user_message = user_message
    @log_content  = log_content
    @sent_at      = sent_at

    mail(
      to:      to,
      subject: "[VulcainVPN] Diagnostic Report — #{user_email} — v#{app_version}"
    )
  end
end
