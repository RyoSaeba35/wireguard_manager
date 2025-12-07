class DownloadsController < ApplicationController
  before_action :authenticate_user!
  skip_forgery_protection only: [:config, :qr_code]

  def qr_code
    filename = params[:filename]
    unless filename.end_with?('.png')
      filename += '.png'
    end
    client_name = filename.gsub('.png', '')
    Rails.logger.info "Filename: #{filename}, Client Name: #{client_name}"
    client = current_user.wireguard_clients.find_by(name: client_name)

    if client && client.qr_code.attached?
      redirect_to rails_blob_path(client.qr_code, disposition: "inline")
    else
      Rails.logger.error "QR code not found for client: #{client_name}"
      redirect_to root_path, alert: "QR code not found."
    end
  end

  def config
    filename = params[:filename]
    filename += '.conf' unless filename.end_with?('.conf')

    client_name = filename.gsub('.conf', '')
    client = current_user.wireguard_clients.find_by(name: client_name)

    if client&.config_file&.attached?
      custom_name = "Vulcain_#{client.name}.conf"

      url = client.config_file.url(
        disposition: :attachment,
        filename: custom_name,
        content_type: "text/x-config"
      )

      # allow redirect to external S3/Wasabi URL
      redirect_to url, allow_other_host: true
    else
      redirect_to root_path, alert: "Config file not found."
    end
  end
end
