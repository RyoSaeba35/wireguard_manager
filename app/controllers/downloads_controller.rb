class DownloadsController < ApplicationController
  before_action :authenticate_user!
  skip_forgery_protection only: [:config, :qr_code]

  def qr_code
    filename = params[:filename]

    # Ensure the filename includes the .png extension
    unless filename.end_with?('.png')
      filename += '.png'
    end

    client_name = filename.gsub('.png', '')

    Rails.logger.info "Filename: #{filename}, Client Name: #{client_name}"

    client = current_user.wireguard_clients.find_by(name: client_name)

    if client
      file_path = Rails.root.join('storage', 'qr_codes', filename)
      Rails.logger.info "File path: #{file_path}, Exists: #{File.exist?(file_path)}"

      if File.exist?(file_path)
        send_file file_path, type: 'image/png', disposition: 'inline'
      else
        Rails.logger.error "QR code file not found: #{file_path}"
        redirect_to root_path, alert: "QR code not found."
      end
    else
      Rails.logger.error "Client not found for name: #{client_name}"
      redirect_to root_path, alert: "Unauthorized access."
    end
  end

  def config
    filename = params[:filename]

    # Ensure the filename includes the .conf extension
    unless filename.end_with?('.conf')
      filename += '.conf'
    end

    client_name = filename.gsub('.conf', '')

    Rails.logger.info "Filename: #{filename}, Client Name: #{client_name}"
    Rails.logger.info "Current User Wireguard Clients: #{current_user.wireguard_clients.pluck(:name)}"

    client = current_user.wireguard_clients.find_by(name: client_name)

    if client
      file_path = Rails.root.join('storage', 'configs', filename)
      Rails.logger.info "File path: #{file_path}, Exists: #{File.exist?(file_path)}"

      if File.exist?(file_path)
        send_file file_path, type: 'application/octet-stream', disposition: 'attachment'
      else
        Rails.logger.error "Config file not found: #{file_path}"
        redirect_to root_path, alert: "Config file not found."
      end
    else
      Rails.logger.error "Client not found for name: #{client_name}"
      redirect_to root_path, alert: "Unauthorized access."
    end
  end
end
