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
    access_token, access_payload = Warden::JWTAuth::UserEncoder.new.call(
      user,
      :user,
      nil
    )

    # Generate refresh token, linked to this access token so logout can revoke
    # this device's session only
    refresh_token = user.generate_refresh_token(access_jti: access_payload["jti"])

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

      # 🔐 A locked account must not keep a session alive through refresh.
      # Checked before consuming, so the token still works once unlocked.
      if user.access_locked?
        render json: {
          error: "Account is locked. Check your email for an unlock link, or try again in 1 hour."
        }, status: :forbidden
        return
      end

      unless user.consume_refresh_token(decoded['jti'])
        render json: { error: "Invalid or expired refresh token" }, status: :unauthorized
        return
      end

      # Generate new access token
      new_access_token, access_payload = Warden::JWTAuth::UserEncoder.new.call(
        user,
        :user,
        nil
      )

      # Generate new refresh token (rotate refresh tokens), linked to the new access token
      new_refresh_token = user.generate_refresh_token(access_jti: access_payload["jti"])

      render json: {
        access_token: new_access_token,
        refresh_token: new_refresh_token,
        user: {
          id: user.id,
          email: user.email
        }
      }, status: :ok

    rescue JWT::DecodeError
      render json: { error: "Invalid refresh token" }, status: :unauthorized
    rescue ActiveRecord::RecordNotFound
      render json: { error: "User not found" }, status: :unauthorized
    end
  end

  # DELETE api/logout
  #
  # ✅ Signs out THIS device only. It used to delete every refresh token the
  # user had, so logging out on Windows also logged out the phone.
  #
  # The current device's refresh token is found through the access token that
  # was issued with it (refresh_tokens.access_jti). The app may also send its
  # refresh token in the body; that one is revoked too.
  def destroy
    token = request.headers['Authorization']&.split(' ')&.last

    if token.present?
      begin
        # Signature is still checked; expiry is not, so a user whose access
        # token just expired can still log out cleanly.
        payload = JWT.decode(
          token,
          ENV['DEVISE_JWT_SECRET_KEY'],
          true,
          { algorithm: 'HS256', verify_expiration: false }
        ).first

        if payload['type'] != 'refresh' && payload['jti'].present?
          JwtDenylist.find_or_create_by!(jti: payload['jti']) do |entry|
            entry.exp = Time.at(payload['exp'].to_i)
          end

          user = User.find(payload['sub'])
          user.refresh_tokens.where(access_jti: payload['jti']).delete_all

          # Tokens issued before this change have no access_jti and cannot be
          # tied to a device; revoke those (one-time, legacy sessions only).
          user.refresh_tokens.where(access_jti: nil).delete_all

          revoke_refresh_token_from_body(user)
        end
      rescue JWT::DecodeError
        Rails.logger.warn "Logout with invalid JWT token"
      rescue ActiveRecord::RecordNotFound
        Rails.logger.warn "User not found during logout"
      end
    end

    render json: { message: "Logged out successfully" }, status: :ok
  end

  private

  def revoke_refresh_token_from_body(user)
    return if params[:refresh_token].blank?

    decoded = JWT.decode(
      params[:refresh_token],
      ENV['DEVISE_JWT_SECRET_KEY'],
      true,
      { algorithm: 'HS256', verify_expiration: false }
    ).first

    return unless decoded['type'] == 'refresh' && decoded['sub'].to_s == user.id.to_s

    user.refresh_tokens.where(jti: decoded['jti']).delete_all
  rescue JWT::DecodeError
    nil
  end
end
