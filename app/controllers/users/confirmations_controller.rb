# app/controllers/users/confirmations_controller.rb
class Users::ConfirmationsController < Devise::ConfirmationsController
  def show
    self.resource = resource_class.confirm_by_token(params[:confirmation_token])
    yield resource if block_given?

    if resource.errors.empty?
      set_flash_message!(:notice, :confirmed)
      respond_with_navigational(resource) do
        sign_in(resource)  # Automatically sign in the user
        redirect_to after_confirmation_path_for(resource_name, resource)
      end
    else
      respond_with_navigational(resource.errors, status: :unprocessable_entity) do
        redirect_to new_session_path(resource_name)
      end
    end
  end

  def after_confirmation_path_for(resource_name, resource)
    dashboard_path  # Redirect to a user-specific page (e.g., dashboard)
  end
end
