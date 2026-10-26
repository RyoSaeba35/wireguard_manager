# app/controllers/api/accounts_controller.rb
#
# Account self-service for the Flutter app:
#   POST   api/password/reset       -> sends the Devise reset email
#   POST   api/confirmation/resend  -> resends the confirmation email
#   POST   api/confirmation         -> confirms an email from the app (App Links)
#   DELETE api/account              -> deletes the account (Google Play requirement)
#
# Reset and resend always answer 200 with the same message (Devise paranoid
# mode), so the API never reveals whether an email is registered.
class Api::AccountsController < ApplicationController
  include ApiJwtAuthenticatable

  skip_before_action :authenticate_user!, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  before_action :authenticate_api_user!, only: [:destroy]

  GENERIC_EMAIL_MESSAGE =
    "If this email is registered, you will receive an email within a few minutes. " \
    "Please check your spam folder."

  # POST api/password/reset
  def reset_password
    email = params[:email].to_s.downcase.strip
    User.send_reset_password_instructions(email: email) if email.present?

    render json: { message: GENERIC_EMAIL_MESSAGE }, status: :ok
  end

  # POST api/confirmation/resend
  def resend_confirmation
    email = params[:email].to_s.downcase.strip
    User.send_confirmation_instructions(email: email) if email.present?

    render json: { message: GENERIC_EMAIL_MESSAGE }, status: :ok
  end

  # POST api/confirmation
  # params: confirmation_token (from the email link, opened in the app)
  def confirm
    token = params[:confirmation_token].to_s
    if token.blank?
      render json: { error: "Missing confirmation token" }, status: :bad_request
      return
    end

    user = User.confirm_by_token(token)

    if user.errors.empty?
      render json: { message: "Email confirmed. You can now sign in.", email: user.email }, status: :ok
    elsif user.persisted? && user.confirmed? && user.errors.added?(:email, :already_confirmed)
      render json: { message: "Email already confirmed. You can sign in.", email: user.email }, status: :ok
    else
      render json: {
        error: "This confirmation link is invalid or has expired. Request a new one from the sign in screen."
      }, status: :unprocessable_entity
    end
  end

  # DELETE api/account
  # params: password (required, re-authentication before an irreversible action)
  def destroy
    user = @current_api_user

    # Goes through :lockable so password guessing here is capped like /api/login
    authenticated = user.valid_for_authentication? { user.valid_password?(params[:password].to_s) }

    unless authenticated
      if user.access_locked?
        render json: { error: "Account is locked after too many failed attempts. Try again in 1 hour." },
               status: :forbidden
      else
        render json: { error: "Incorrect password" }, status: :unauthorized
      end
      return
    end

    AccountDeletionService.new(user).call!

    render json: { message: "Your account has been deleted." }, status: :ok
  rescue StandardError => e
    Rails.logger.error "[AccountDeletion] API failed for user #{user&.id}: #{e.class} #{e.message}"
    render json: { error: "Account deletion failed. Please contact support@vulcainvpn.com" },
           status: :internal_server_error
  end
end
