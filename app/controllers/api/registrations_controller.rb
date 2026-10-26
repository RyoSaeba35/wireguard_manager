# app/controllers/api/registrations_controller.rb
#
# Account creation from the Flutter app.
# Same User model and Devise rules as the website: :confirmable sends the
# confirmation email automatically, and /api/login refuses unconfirmed users,
# so no tokens are returned here. The app shows a "check your email" screen.
class Api::RegistrationsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  # POST api/signup
  # params: email, password, password_confirmation (optional)
  def create
    email = params[:email].to_s.downcase.strip
    password = params[:password].to_s

    user = User.new(
      email: email,
      password: password,
      password_confirmation: params[:password_confirmation].presence || password
    )

    if user.save
      render json: {
        message: "Account created. Check your email to confirm your address, then sign in.",
        email: user.email
      }, status: :created
    else
      render json: {
        error: user.errors.full_messages.first,
        errors: user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
end
