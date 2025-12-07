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
      # Create a temporary file to hold the config data
      temp_file = Tempfile.new(["config_#{SecureRandom.hex}", '.conf'])
      temp_file.binmode
      temp_file.write(client.config_file.download)
      temp_file.close

      # Set proper response headers
      response.headers['Content-Type'] = 'text/x-config'
      response.headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
      response.headers['Content-Length'] = temp_file.size.to_s
      response.headers['Cache-Control'] = 'private'
      response.headers['Last-Modified'] = File.mtime(temp_file.path).httpdate

      # Send the file
      send_file temp_file.path, filename: filename, disposition: 'attachment', type: 'text/x-config'
    else
      Rails.logger.error "Config file not found for client: #{client_name}"
      redirect_to root_path, alert: "Config file not found."
    end
  ensure
    # Clean up the temp file
    temp_file&.close!
  end
end
