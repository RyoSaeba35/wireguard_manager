# app/controllers/admin/subscriptions_controller.rb
module Admin
  class SubscriptionsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :set_user, only: [:create]

    def create
      server = Server.find(params[:subscription][:server_id])
      plan = Plan.find(params[:subscription][:plan_id])
      expires_at = params[:subscription][:expires_at]

      # Always use preallocated — same as regular user flow
      preallocated = server.subscriptions.preallocated.first

      unless preallocated
        render json: {
          success: false,
          error: "No preallocated subscriptions available on #{server.name}. Run PreallocateSubscriptionsJob first."
        }, status: :unprocessable_entity
        return
      end

      preallocated.update!(
        user_id: @user.id,
        status: "active",  # Admin-created subscriptions skip payment
        plan_id: plan.id,
        price: plan.price,
        expires_at: expires_at
      )

      server.increment!(:current_subscriptions)

      render json: {
        success: true,
        subscription: {
          id: preallocated.id,
          name: preallocated.name,
          plan: plan.name,
          server: server.name,
          expires_at: preallocated.expires_at.strftime("%d %b %Y"),
          status: preallocated.status
        }
      }
    end

    def cancel
      @subscription = Subscription.find(params[:id])

      # Full revocation — remove from server, purge files, no pool return
      CancelSubscriptionJob.perform_later(@subscription.id)

      render json: { success: true }
    end

    private

    def require_admin
      unless current_user.admin?
        redirect_to root_path, alert: "Access denied."
      end
    end

    def set_user
      @user = User.find(params[:user_id])
    end

    def subscription_params
      params.require(:subscription).permit(:plan_id, :server_id, :expires_at)
    end
  end
end
