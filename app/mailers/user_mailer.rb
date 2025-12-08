# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  default from: 'Vulcain VPN <support@vulcainvpn.com>' # Use a valid email address

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

    # Attach the logo as an inline image
    logo_path = Rails.root.join('app/assets/images/Vulcain_VPN_logo_3.png')
    if File.exist?(logo_path)
      attachments.inline['Vulcain_VPN_logo_3.png'] = File.read(logo_path)
    else
      Rails.logger.error "Logo not found at #{logo_path}"
    end

    mail(to: @user.email, subject: "Welcome to Vulcain VPN – Your Secure Connection is Ready!")
  end
end
