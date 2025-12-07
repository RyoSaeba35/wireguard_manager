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

      temp_file = Tempfile.new(["config_#{SecureRandom.hex}", '.conf'])
      temp_file.binmode
      temp_file.write(file_data)
      temp_file.close

      send_file temp_file.path,
                filename: filename,
                disposition: 'attachment',
                type: 'text/x-config',
                x_sendfile: true
    else
      Rails.logger.error "Config file not found for client: #{client_name}"
      redirect_to root_path, alert: "Config file not found."
    end
  ensure
    temp_file&.close!
    temp_file&.unlink
  end
end
