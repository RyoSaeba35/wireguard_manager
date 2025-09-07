# app/controllers/subscriptions_controller.rb
class SubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def new
    if current_user.subscriptions.where(status: 'active').exists?
      @existing_subscription = current_user.subscriptions.find_by(status: 'active')
      redirect_to user_subscription_path(current_user, @existing_subscription),
                  alert: "You already have an active subscription to #{@existing_subscription.plan.name}."
      return
    end
    @plans = Plan.all
    @subscription = current_user.subscriptions.new
  end

  def create
    selected_plan = Plan.find(subscription_params[:plan_id])
    max_limit = Setting.max_active_subscriptions

    # Check global subscription limit
    if Subscription.where(status: 'active').count >= max_limit
      redirect_to new_user_subscription_path(current_user),
                  alert: "We limit the number of active subscriptions to ensure the best quality of service. Please try again later."
      return
    end

    # Check if there are available servers
    unless Server.where(active: true).where("current_subscriptions < max_subscriptions").exists?
      redirect_to new_user_subscription_path(current_user),
                  alert: "No servers are available at the moment. Please try again later."
      return
    end

    # Generate a unique 6-character alphanumeric token for the subscription
    subscription_name = loop do
      random_name = SecureRandom.alphanumeric(6).upcase
      break random_name unless Subscription.exists?(name: random_name)
    end

    Rails.logger.info "Creating subscription: #{subscription_name}"

    # Use the service to create the subscription and wireguard client
    creator = SubscriptionCreator.new(current_user, subscription_name, subscription_params)
    @subscription = creator.call

    if @subscription.persisted?
      redirect_to user_subscription_path(current_user, @subscription),
                  notice: "Subscription and WireGuard client created successfully."
    else
      Rails.logger.error "Failed to create subscription: #{@subscription&.errors&.full_messages || 'Unknown error'}"
      render :new
    end
  end

  def show
    @subscription = current_user.subscriptions.find(params[:id])
    @wireguard_clients = @subscription.wireguard_clients
    @wireguard_client = @wireguard_clients.first if @wireguard_clients.any?
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan_id, :price)
  end
end
