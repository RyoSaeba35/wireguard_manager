# app/controllers/downloads_controller.rb
class DownloadsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:apk]
  before_action :authenticate_user!, except: [:apk]

  def apk
    require 'aws-sdk-s3'

    # Use Presigner, not Client
    signer = Aws::S3::Presigner.new(
      region: ENV['AWS_REGION'],
      endpoint: ENV['AWS_ENDPOINT'],
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )

    # Generate a signed URL that expires in 1 hour
    presigned_url = signer.presigned_url(
      :get_object,
      bucket: ENV['AWS_BUCKET'],
      key: 'downloads/VulcainVPN-1.0.0.apk',
      expires_in: 3600
    )

    # Redirect to the signed URL
    redirect_to presigned_url, allow_other_host: true
  rescue => e
    Rails.logger.error "Failed to generate APK download URL: #{e.message}"
    redirect_to root_path, alert: 'Download failed. Please try again.'
  end

  def qr_code
    redirect_to root_path, alert: "QR codes are no longer available. Please use the mobile app to connect."
  end

  def config
    redirect_to root_path, alert: "Config files are no longer available for download. Please use the VPN app to connect."
  end
end
