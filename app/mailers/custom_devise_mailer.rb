# app/mailers/custom_devise_mailer.rb
class CustomDeviseMailer < Devise::Mailer
  include Devise::Controllers::UrlHelpers

  default from: 'Vulcain VPN <support@vulcainvpn.com>'

  def confirmation_instructions(record, token, opts = {})
    @token = token
    @resource = record
    attach_logo
    super # This calls the original Devise mailer method
  end

  private

  def attach_logo
    logo_path = Rails.root.join('app/assets/images/Vulcain_VPN_logo_3.png')
    if File.exist?(logo_path)
      attachments.inline['Vulcain_VPN_logo_3.png'] = File.read(logo_path)
    else
      Rails.logger.error "Logo not found at #{logo_path}"
    end
  end
end
