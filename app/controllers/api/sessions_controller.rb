# app/controllers/api/sessions_controller.rb
class Api::SessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token

  # POST api/login
  #
  # 🔐 Goes through Devise's `valid_for_authentication?` so the :lockable
  # module counts failed attempts and locks the account after
  # `config.maximum_attempts` (5). The old code called `valid_password?`
  # directly, which skipped the counter entirely: unlimited guesses.
  # Per-IP and per-email throttling is in config/initializers/rack_attack.rb.
  def create
    user = User.find_by(email: params[:email].to_s.downcase.strip)

    unless user
      render json: { error: "Invalid email or password" }, status: :unauthorized
      return
    end

    # Also unlocks the account first if the :time unlock period has passed
    authenticated = user.valid_for_authentication? { user.valid_password?(params[:password].to_s) }

    unless authenticated
      if user.access_locked?
        render json: {
          error: "Account is locked after too many failed attempts. " \
                 "Check your email for an unlock link, or try again in 1 hour."
        }, status: :forbidden
      else
        render json: { error: "Invalid email or password" }, status: :unauthorized
      end
      return
    end

    unless user.confirmed?
      render json: { error: "Please confirm your email before logging in" }, status: :forbidden
      return
    end

    # Successful login: reset the failed-attempts counter. Devise does this in
    # a Warden hook for web logins, but the API doesn't go through Warden.
    user.update_column(:failed_attempts, 0) if user.failed_attempts.to_i.positive?

    # Generate access token (JWT)
    access_token, _payload = Warden::JWTAuth::UserEncoder.new.call(
      user,
      :user,
      nil
    )

    # Generate refresh token
    refresh_token = user.generate_refresh_token

    # Clean up old expired tokens
    user.cleanup_refresh_tokens

    render json: {
      access_token: access_token,
      refresh_token: refresh_token,
      user: {
        id: user.id,
        email: user.email
      }
    }, status: :ok
  end

  # POST api/refresh
  def refresh
    refresh_token = params[:refresh_token]

    unless refresh_token.present?
      render json: { error: "Refresh token required" }, status: :bad_request
      return
    end

    begin
      # Decode refresh token
      decoded = JWT.decode(
        refresh_token,
        ENV['DEVISE_JWT_SECRET_KEY'],
        true,
        { algorithm: 'HS256' }
      ).first

      # Verify it's a refresh token
      unless decoded['type'] == 'refresh'
        render json: { error: "Invalid token type" }, status: :unauthorized
        return
      end

      # Find user and validate token
      user = User.find(decoded['sub'])

      unless user.consume_refresh_token(decoded['jti'])
        render json: { error: "Invalid or expired refresh token" }, status: :unauthorized
        return
      end

      # Generate new access token
      new_access_token, _payload = Warden::JWTAuth::UserEncoder.new.call(
        user,
        :user,
        nil
      )

      # Generate new refresh token (rotate refresh tokens)
      new_refresh_token = user.generate_refresh_token

      render json: {
        access_token: new_access_token,
        refresh_token: new_refresh_token,
        user: {
          id: user.id,
          email: user.email
        }
      }, status: :ok

    rescue JWT::DecodeError => e
      render json: { error: "Invalid refresh token" }, status: :unauthorized
    rescue ActiveRecord::RecordNotFound
      render json: { error: "User not found" }, status: :unauthorized
    end
  end

  # DELETE api/logout
  def destroy
    token = request.headers['Authorization']&.split(' ')&.last

    if token.present?
      begin
        payload = JWT.decode(
          token,
          ENV['DEVISE_JWT_SECRET_KEY'],
          true,
          algorithm: 'HS256'
        ).first

        JwtDenylist.create!(
          jti: payload['jti'],
          exp: Time.at(payload['exp'])
        )

        # Revoke all refresh tokens for this user
        user = User.find(payload['sub'])
        user.refresh_tokens.destroy_all

      rescue JWT::DecodeError
        Rails.logger.warn "Logout with invalid JWT token"
      rescue ActiveRecord::RecordNotFound
        Rails.logger.warn "User not found during logout"
      end
    end

    render json: { message: "Logged out successfully" }, status: :ok
  end
end
