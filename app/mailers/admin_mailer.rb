# app/mailers/admin_mailer.rb
class AdminMailer < ApplicationMailer
  default from: 'Vulcain VPN <support@vulcainvpn.com>'

  def password_theft_alert(username:, geolocations:, client:)
    @username = username
    @geolocations = geolocations
    @client = client
    @device = client.device
    @user = @device&.user

    @locations_summary = geolocations.map do |g|
      "#{g[:ip]} (#{g[:geo][:city]}, #{g[:geo][:country]})"
    end.join(' AND ')

    mail(
      to: 'admin@vulcainvpn.com',
      subject: "🚨 URGENT: Password Theft Detected - #{username}"
    )
  end

  def server_recovered(server)
    @server = server
    mail(
      to: 'admin@vulcainvpn.com',
      subject: "✅ Server Recovered: #{server.name}"
    )
  end
end
