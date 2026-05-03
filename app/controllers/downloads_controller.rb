# app/controllers/downloads_controller.rb
class DownloadsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :apk, :windows, :file ]
  before_action :authenticate_user!, except: [ :apk, :windows, :file ]

  # Generic download method
  def file
    filename = params[:filename]

    # Validate filename (security: prevent path traversal)
    unless filename.match?(/^[a-zA-Z0-9._-]+\.(apk|exe|dmg|zip|deb|rpm)$/)
      redirect_to root_path, alert: "Invalid file requested."
      return
    end

    generate_download_url("downloads/#{filename}")
  end

  # Specific endpoints for clean URLs
  def apk
    generate_download_url("downloads/VulcainVPN-1.0.6.apk")
  end

  def windows
    generate_download_url("downloads/VulcainVPN-Setup-1.0.6.exe")
  end

  def qr_code
    redirect_to root_path, alert: "QR codes are no longer available. Please use the mobile app to connect."
  end

  def config
    redirect_to root_path, alert: "Config files are no longer available for download. Please use the VPN app to connect."
  end

  private

  def generate_download_url(key)
    require "aws-sdk-s3"

    s3_client = Aws::S3::Client.new(
      region: ENV["AWS_REGION"],
      endpoint: ENV["AWS_ENDPOINT"],
      access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
      force_path_style: true
    )

    signer = Aws::S3::Presigner.new(client: s3_client)

    presigned_url = signer.presigned_url(
      :get_object,
      bucket: ENV["AWS_BUCKET"],
      key: key,
      expires_in: 3600
    )

    redirect_to presigned_url, allow_other_host: true
  rescue => e
    Rails.logger.error "Failed to generate download URL for #{key}: #{e.message}"
    redirect_to root_path, alert: "Download failed. Please try again."
  end
end
