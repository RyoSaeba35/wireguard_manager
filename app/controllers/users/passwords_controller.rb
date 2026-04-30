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

    if successfully_sent?(resource)
      # Successfully sent (or pretending to - paranoid mode)
      respond_with({}, location: after_sending_reset_password_instructions_path_for(resource_name))
    else
      # Handle errors better
      if resource.errors.empty?
        # Paranoid mode: no errors shown, but email wasn't found
        # Show a helpful message instead of blank error
        flash.now[:alert] = "If this email is registered with Vulcain VPN, you'll receive password reset instructions within a few minutes. Please check your spam folder."
      end
      respond_with(resource)
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
