# app/controllers/api/sessions_controller.rb
class Api::SessionsController < ApplicationController
  protect_from_forgery with: :null_session

  # POST api/login
  def create
    user = User.find_by(email: params[:email]&.downcase)

    unless user&.valid_password?(params[:password])
      render json: { error: "Invalid email or password" }, status: :unauthorized
      return
    end

    unless user.confirmed?
      render json: { error: "Please confirm your email before logging in" }, status: :forbidden
      return
    end

    if user.locked_at.present?
      render json: { error: "Account is locked. Please contact support." }, status: :forbidden
      return
    end

    # Use Devise JWT to generate token — respects JwtDenylist automatically
    token, _payload = Warden::JWTAuth::UserEncoder.new.call(
      user,
      :user,
      nil
    )

    render json: {
      token: token,
      user: {
        id: user.id,
        email: user.email
      }
    }, status: :ok
  end

  # DELETE api/logout
  def destroy
    token = request.headers['Authorization']&.split(' ')&.last

    if token.present?
      begin
        payload = JWT.decode(
          token,
          Rails.application.credentials.devise_jwt_secret_key,
          true,
          algorithm: 'HS256'
        ).first

        JwtDenylist.create!(
          jti: payload['jti'],
          exp: Time.at(payload['exp'])
        )
      rescue JWT::DecodeError
        # Token already invalid — fine, just log out
        Rails.logger.warn "Logout with invalid JWT token"
      end
    end

    render json: { message: "Logged out successfully" }, status: :ok
  end
end
