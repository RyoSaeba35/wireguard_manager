# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  # GET /resource/password/new
  # def new
  #   super
  # end

  # POST /resource/password
  def create
    self.resource = resource_class.send_reset_password_instructions(resource_params)
    yield resource if block_given?

    # ALWAYS show the same message for security (paranoid mode)
    # This prevents attackers from determining which emails are registered
    if successfully_sent?(resource)
      # Email was sent successfully
      set_flash_message! :notice, :send_paranoid_instructions
      respond_with({}, location: after_sending_reset_password_instructions_path_for(resource_name))
    else
      # Email not found OR there was an error
      # STILL show the same message to prevent email enumeration
      flash.now[:notice] = "If this email is registered with Vulcain VPN, you'll receive password reset instructions within a few minutes. Please check your spam folder."

      # Clear any errors to avoid showing them
      resource.errors.clear

      # Re-render the form with the notice message
      render :new
    end
  end

  # GET /resource/password/edit?reset_password_token=abcdef
  # def edit
  #   super
  # end

  # PUT /resource/password
  # def update
  #   super
  # end

  # protected

  # def after_resetting_password_path_for(resource)
  #   super(resource)
  # end

  # The path used after sending reset password instructions
  # def after_sending_reset_password_instructions_path_for(resource_name)
  #   super(resource_name)
  # end
end
