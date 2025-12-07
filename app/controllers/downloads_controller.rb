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
    client_name = filename.gsub('.conf', '').gsub('Vulcain_', '')
    Rails.logger.info "Filename: #{filename}, Client Name: #{client_name}"

    client = current_user.wireguard_clients.find_by(name: client_name)
    if client && client.config_file.attached?
      file_data = client.config_file.download

      if file_data.blank?
        Rails.logger.error "Config file data is empty for client: #{client_name}"
        redirect_to root_path, alert: "Config file is empty."
        return
      end

      Rails.logger.info "File data size: #{file_data.bytesize}"

      response.headers['Content-Type'] = 'text/x-config'
      response.headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
      response.headers['Content-Length'] = file_data.bytesize.to_s

      send_data file_data, type: 'text/x-config', disposition: 'attachment'
    else
      Rails.logger.error "Config file not found for client: #{client_name}"
      redirect_to root_path, alert: "Config file not found."
    end
  end
end
