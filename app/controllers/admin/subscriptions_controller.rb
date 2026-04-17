# app/controllers/admin/subscriptions_controller.rb
module Admin
  class SubscriptionsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :set_user, only: [:create]

    def create
      plan = Plan.find(params[:subscription][:plan_id])
      expires_at = params[:subscription][:expires_at]

      # ⭐ NEW: Check global capacity
      unless SystemSetting.can_accept_new_subscription?
        render json: {
          success: false,
          error: "System at capacity. Cannot create new subscription."
        }, status: :unprocessable_entity
        return
      end

      # ⭐ NEW: Generate unique name
      subscription_name = loop do
        name = "ADMIN_#{SecureRandom.alphanumeric(5).upcase}"
        break name unless Subscription.exists?(name: name)
      end

      # ⭐ NEW: Create subscription directly (no preallocated, no server)
      subscription = @user.subscriptions.create!(
        name: subscription_name,
        status: "active",  # Admin-created skip payment
        plan: plan,
        price: plan.price,
        expires_at: expires_at,
        max_devices: 3
      )

      render json: {
        success: true,
        subscription: {
          id: subscription.id,
          name: subscription.name,
          plan: plan.name,
          expires_at: subscription.expires_at.strftime("%d %b %Y"),
          status: subscription.status
        }
      }
    end

    def cancel
      @subscription = Subscription.find(params[:id])

      # Release all active configs back to pool
      @subscription.devices.each do |device|
        if device.vpn_config_set
          device.vpn_config_set.release!
        end
      end

      # Mark subscription as expired
      @subscription.update!(
        status: "expired",
        expires_at: Time.current
      )

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
      params.require(:subscription).permit(:plan_id, :expires_at)
    end
  end
end
