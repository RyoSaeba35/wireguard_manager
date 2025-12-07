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
    unless filename.end_with?('.conf')
      filename += '.conf'
    end
    # Remove "Vulcain_" prefix before extracting client_name
    client_name = filename.gsub('.conf', '').gsub('Vulcain_', '')
    Rails.logger.info "Filename: #{filename}, Client Name: #{client_name}"

    Rails.logger.info "Current User Wireguard Clients: #{current_user.wireguard_clients.pluck(:name)}"
    client = current_user.wireguard_clients.find_by(name: client_name)

    if client && client.config_file.attached?
      # Force the downloaded filename to match the requested `filename`
      response.headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
      redirect_to rails_blob_path(client.config_file, disposition: "attachment")
    else
      Rails.logger.error "Config file not found for client: #{client_name}"
      redirect_to root_path, alert: "Config file not found."
    end
  end
end
