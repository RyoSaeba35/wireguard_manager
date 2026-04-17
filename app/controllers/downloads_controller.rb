# app/controllers/downloads_controller.rb
class DownloadsController < ApplicationController
  before_action :authenticate_user!

  # ⭐ NEW: These endpoints no longer work with pooling
  # Configs are only available via API when connected

  def qr_code
    redirect_to root_path, alert: "QR codes are no longer available. Please use the mobile app to connect."
  end

  def config
    redirect_to root_path, alert: "Config files are no longer available for download. Please use the VPN app to connect."
  end
end
