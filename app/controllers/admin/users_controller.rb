module Admin
  class UsersController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :set_user, only: [:destroy]

    def index
      @users = User.includes(subscriptions: [:plan, :server, :wireguard_clients]).order(:email)
      @plans = Plan.order(price: :asc)
      @servers = Server.all
    end

    def create
      @user = User.new(user_params)
      if @user.save
        render json: { success: true }
      else
        render json: { success: false, error: @user.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    def destroy
      # Prevent admin from deleting themselves
      if @user.id == current_user.id
        return render json: {
          success: false,
          error: "You cannot delete your own account",
          code: "self_deletion"
        }, status: :unprocessable_entity
      end

      # Check if user has active subscriptions
      if @user.subscriptions.active.any?
        return render json: {
          success: false,
          error: "User has active subscriptions. Cancel them first.",
          code: "active_subscriptions"
        }, status: :unprocessable_entity
      end

      begin
        if @user.destroy
          render json: {
            success: true,
            email: @user.email,  # Add the user's email to the response
            id: @user.id        # Add the user's ID to the response
          }
        else
          render json: {
            success: false,
            error: @user.errors.full_messages.join(', '),
            code: "destroy_failed"
          }, status: :unprocessable_entity
        end
      rescue => e
        render json: {
          success: false,
          error: e.message,
          code: "exception",
          backtrace: Rails.env.development? ? e.backtrace : nil
        }, status: :internal_server_error
      end
    end

    private

    def require_admin
      unless current_user.admin?
        redirect_to root_path, alert: "Access denied."
      end
    end

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email)
    end
  end
end
