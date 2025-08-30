class UsersController < ApplicationController
  before_action :authenticate_user! # Ensure user is authenticated

  # # Example: Custom user dashboard
  # def dashboard
  #   # Your custom logic here, e.g., fetch user-specific data
  #   @user = current_user
  # end

  # Example: Custom profile page
  def profile
    @user = current_user
  end

  # Example: Update user profile
  def update_profile
    if params[:user][:password].blank?
      # Only update email if password is blank
      if current_user.update_with_password(user_params.except(:password, :password_confirmation))
        bypass_sign_in(current_user) # Keep the user signed in
        redirect_to profile_path, notice: "Email updated successfully!"
      else
        render :profile
      end
    else
      # Update both email and password if password is provided
      if current_user.update_with_password(user_params)
        bypass_sign_in(current_user) # Keep the user signed in
        redirect_to profile_path, notice: "Profile updated successfully!"
      else
        render :profile
      end
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :current_password)
  end
end
