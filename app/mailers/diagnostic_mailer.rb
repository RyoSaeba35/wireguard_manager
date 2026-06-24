# app/mailers/diagnostic_mailer.rb
class DiagnosticMailer < ApplicationMailer
  default from: 'VulcainVPN Support <support@vulcainvpn.com>'

  def report(to:, user_email:, user_id:, device_info:, os_version:,
             app_version:, user_message:, log_content:, sent_at:)
    @user_email   = user_email
    @user_id      = user_id
    @device_info  = device_info
    @os_version   = os_version
    @app_version  = app_version
    @user_message = user_message
    @sent_at      = sent_at

    # Attach log as a .txt file instead of dumping it in the email body
    attachments["vulcainvpn_diagnostic_#{user_id}_#{Time.current.strftime('%Y%m%d_%H%M')}.txt"] = {
      mime_type: 'text/plain',
      content:   log_content
    }

    mail(
      to:      to,
      subject: "[VulcainVPN] Diagnostic Report — #{user_email} — v#{app_version}"
    )
  end
end
