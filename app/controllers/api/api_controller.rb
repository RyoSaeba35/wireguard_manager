module Api
  class BaseController < ActionController::API
    before_action :ensure_json_request
    before_action :authenticate_request!

    attr_reader :current_user, :current_device

    private

    # ----------------------------
    # JSON only
    # ----------------------------
    def ensure_json_request
      request.format = :json
    end

    # ----------------------------
    # Authentication dispatcher
    # ----------------------------
    def authenticate_request!
      authenticate_with_jwt || authenticate_with_api_key || render_unauthorized
    end

    # ----------------------------
    # JWT auth (Flutter app)
    # ----------------------------
    def authenticate_with_jwt
      authenticate_user!
      @current_user = current_user
      @current_user.present?
    rescue JWT::DecodeError, JWT::ExpiredSignature
      false
    end

    # ----------------------------
    # API key auth (devices / servers)
    # ----------------------------
    def authenticate_with_api_key
      api_key = request.headers['X-API-KEY']
      return false if api_key.blank?

      @current_device = Device.find_by(api_key: api_key)
      @current_user = @current_device&.user

      @current_user.present?
    end

    # ----------------------------
    # Unauthorized response
    # ----------------------------
    def render_unauthorized
      render json: {
        success: false,
        error: 'Unauthorized'
      }, status: :unauthorized
    end
  end
end
