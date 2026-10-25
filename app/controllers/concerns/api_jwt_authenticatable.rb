# app/controllers/concerns/api_jwt_authenticatable.rb
#
# Single source of truth for JWT authentication on the Flutter API.
# Replaces the three copy-pasted `authenticate_api_user!` methods that lived in
# Api::DevicesController, Api::SubscriptionsController and Api::DiagnosticsController.
#
# Security fix: refresh tokens (type: "refresh", valid 30 days) were accepted
# as access tokens because the old code never checked the `type` claim.
# A refresh token is now rejected here; it is only valid at POST /api/refresh.
module ApiJwtAuthenticatable
  extend ActiveSupport::Concern

  private

  def authenticate_api_user!
    token = request.headers["Authorization"]&.split(" ")&.last

    unless token.present?
      render json: { error: "Authorization token required" }, status: :unauthorized
      return
    end

    payload = JWT.decode(
      token,
      ENV["DEVISE_JWT_SECRET_KEY"],
      true,
      algorithm: "HS256"
    ).first

    # Refresh tokens must never authenticate API calls
    if payload["type"] == "refresh"
      render json: { error: "Invalid token type" }, status: :unauthorized
      return
    end

    if JwtDenylist.exists?(jti: payload["jti"])
      render json: { error: "Token has been revoked" }, status: :unauthorized
      return
    end

    @current_api_user = User.find(payload["sub"])
  rescue JWT::DecodeError, ActiveRecord::RecordNotFound
    render json: { error: "Invalid or expired token" }, status: :unauthorized
  end
end
