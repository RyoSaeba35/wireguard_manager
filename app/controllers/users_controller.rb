class UsersController < ApplicationController
  before_action :authenticate_user! # Ensure user is authenticated

  # Example: Custom user dashboard
  def dashboard
    # Your custom logic here, e.g., fetch user-specific data
    @user = current_user
  end

  # Example: Custom profile page
  def profile
    @user = current_user
  end

  # Example: Update user profile
  def update_profile
    @user = current_user
    if @user.update(user_params)
      redirect_to profile_path, notice: "Profile updated successfully!"
    else
      render :profile, alert: "Failed to update profile."
    end
  end

  private

  # Strong parameters for user updates
  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :other_attributes)
  end
end
