class Users::RegistrationsController < Devise::RegistrationsController
  def create
    build_resource(sign_up_params)

    resource.save
    yield resource if block_given?

    if resource.persisted?
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up_but_unconfirmed
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :signed_up_but_unconfirmed
        expire_data_after_sign_in!
        redirect_to new_user_session_path
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end

  # DELETE /users ("Delete my account" on the profile page).
  # Devise's default calls resource.destroy, which fails on foreign keys once
  # the user has devices or VPN history. Same cleanup as DELETE /api/account.
  # This page is also the account deletion URL declared in Google Play.
  def destroy
    AccountDeletionService.new(resource).call!
    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    set_flash_message! :notice, :destroyed
    yield resource if block_given?
    respond_with_navigational(resource) do
      redirect_to after_sign_out_path_for(resource_name), status: Devise.responder.redirect_status
    end
  end
end
