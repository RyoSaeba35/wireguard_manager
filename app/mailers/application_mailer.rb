# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: 'Vulcain VPN <support@vulcainvpn.com>'
  layout "mailer"
end
