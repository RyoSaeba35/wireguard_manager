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

    # Select a server
    server = Server.where(active: true)
                  .where("current_subscriptions < max_subscriptions")
                  .order(:current_subscriptions)
                  .first

    # Calculate expires_at
    expires_at = case selected_plan.interval
                 when 'week'  then 1.week.from_now
                 when 'month' then 1.month.from_now
                 when 'year'  then 1.year.from_now
                 else 1.month.from_now
    end

    # Create the subscription record immediately
    @subscription = current_user.subscriptions.new(
      subscription_params.merge(
        name: subscription_name,
        status: 'pending',
        server: server,
        expires_at: expires_at,
        plan: selected_plan
      )
    )

    if @subscription.save
      # Increment the server's current_subscriptions counter
      server.increment!(:current_subscriptions)

      # Enqueue the background job to create WireGuard clients
      WireguardClientCreationJob.perform_later(@subscription.id)

      redirect_to user_subscription_path(current_user, @subscription),
                  notice: "Subscription created! Your VPN config will be ready in a few minutes. You'll receive an email with your config files."
    else
      Rails.logger.error "Failed to create subscription: #{@subscription.errors.full_messages.join(', ')}"
      @plans = Plan.all
      render :new, status: :unprocessable_entity
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
