# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  default from: 'Vulcain VPN'

  def vpn_config_ready(user, subscription)
    @user = user
    @subscription = subscription
    # Attach the PDF
    pdf_path = Rails.root.join('public', 'pdfs', 'Vulcain_VPN_Setup_Guide.pdf')
    if File.exist?(pdf_path)
      attachments['Vulcain_VPN_Setup_Guide.pdf'] = File.read(pdf_path)
    else
      Rails.logger.error "PDF not found at #{pdf_path}"
    end
    # Use `attachments.inline` instead of `attachments`
    attachments.inline['logo.png'] = File.read(Rails.root.join('app/assets/images/logo.png'))
    mail(to: @user.email, subject: "Your Vulcain VPN Configuration is Ready!")
  end
end
