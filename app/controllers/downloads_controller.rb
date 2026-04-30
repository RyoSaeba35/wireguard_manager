# app/controllers/downloads_controller.rb
class DownloadsController < ApplicationController
  before_action :authenticate_user!, except: [:apk]
  skip_before_action :verify_authenticity_token, only: [:apk]

  # ⭐ NEW: These endpoints no longer work with pooling
  # Configs are only available via API when connected
  def apk
    require 'aws-sdk-s3'

    s3 = Aws::S3::Client.new(
      region: ENV['AWS_REGION'],
      endpoint: ENV['AWS_ENDPOINT'],
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )

    # Get the file from Wasabi
    obj = s3.get_object(bucket: ENV['AWS_BUCKET'], key: 'downloads/VulcainVPN-1.0.0.apk')

    # Stream it to the user
    send_data obj.body.read,
              filename: 'VulcainVPN-1.0.0.apk',
              type: 'application/vnd.android.package-archive',
              disposition: 'attachment'
  rescue => e
    Rails.logger.error "Failed to download APK: #{e.message}"
    redirect_to root_path, alert: 'Download failed. Please try again.'
  end

  def qr_code
    redirect_to root_path, alert: "QR codes are no longer available. Please use the mobile app to connect."
  end

  def config
    redirect_to root_path, alert: "Config files are no longer available for download. Please use the VPN app to connect."
  end
end
