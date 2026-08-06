class UserMailer < ApplicationMailer
  default from: "Vulcain VPN <support@vulcainvpn.com>"

  def subscription_activated(user, subscription, invite_review: true)
    @user = user
    @subscription = subscription
    attach_logo
    bcc_addr = ENV["TRUSTPILOT_BCC"] if Rails.env.production? && invite_review
    mail(to: @user.email, bcc: bcc_addr,
         subject: "Welcome to Vulcain VPN – Your Secure Connection is Ready!",
         template_name: "vpn_config_ready")
  end

  def payment_failed(user, subscription)
    @user = user
    @subscription = subscription
    attach_logo
    mail(to: @user.email,
         subject: "Action needed: your Vulcain VPN payment couldn't be processed")
  end

  private

  def attach_logo
    logo_path = Rails.root.join("app/assets/images/Vulcain_VPN_logo_3.png")
    attachments.inline["Vulcain_VPN_logo_3.png"] = File.read(logo_path) if File.exist?(logo_path)
  end
end
