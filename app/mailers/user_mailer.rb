# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  def vpn_config_ready(user, subscription)
    @user = user
    @subscription = subscription
    # Attach the PDF
    pdf_path = Rails.root.join('public', 'pdfs', 'Fenguard_VPN_Setup_Guide.pdf')
    if File.exist?(pdf_path)
      attachments['Fenguard_VPN_Setup_Guide.pdf'] = File.read(pdf_path)
    else
      Rails.logger.error "PDF not found at #{pdf_path}"
    end
    mail(to: @user.email, subject: "Your Fenguard VPN Configuration is Ready!")
  end
end
