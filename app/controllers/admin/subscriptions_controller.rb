# app/controllers/admin/subscriptions_controller.rb
module Admin
  class SubscriptionsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :set_user, only: [:create]

    def create

      # Génère TOUJOURS un nom aléatoire (ignore le nom fourni)
      subscription_name = loop do
        random_name = SecureRandom.alphanumeric(5).upcase
        break random_name unless Subscription.exists?(name: random_name)
      end

      @subscription = @user.subscriptions.new(subscription_params)
      @subscription.status = 'pending'  # Admin-created subscriptions are active by default

      # Définir le prix à partir du plan sélectionné
      @subscription.price = @subscription.plan.price
      @subscription.name = subscription_name

      if @subscription.save
        render json: {
          success: true,
          subscription: {
            id: @subscription.id,
            name: subscription_name,
            price: @subscription.price,
            plan: @subscription.plan.name,
            server: @subscription.server.name,
            expires_at: @subscription.expires_at.strftime("%d %b %Y"),
            status: @subscription.status
          }
        }
        @subscription.server.increment!(:current_subscriptions)
        WireguardClientCreationJob.perform_later(@subscription.id)
        # Wait for 1.5 seconds before redirecting
        sleep(5)
        @subscription.update!(status: 'active')
      else
        render json: {
          success: false,
          error: @subscription.errors.full_messages.join(', ')
        }, status: :unprocessable_entity
      end
    end

    def cancel
      @subscription = Subscription.find(params[:id])

      if @subscription.update(status: 'canceled', expires_at: Time.current)
        CancelSubscriptionJob.perform_later(@subscription.id)
        render json: { success: true }
      else
        render json: {
          success: false,
          error: @subscription.errors.full_messages.join(', ')
        }, status: :unprocessable_entity
      end
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
      params.require(:subscription).permit(:name, :plan_id, :server_id, :expires_at)
    end
  end
end
