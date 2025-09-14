class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_subscription, only: [:show]
  before_action :authorize_subscription, only: [:show]

  def new
    # Only block if the user has a truly active (non-expired) or pending subscription
    if current_user.subscriptions.where("status IN (?) AND expires_at > ?", ['active', 'pending'], Time.current).exists?
      @existing_subscription = current_user.subscriptions.where("status IN (?) AND expires_at > ?", ['active', 'pending'], Time.current).first
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

    # Only count truly active (non-expired) subscriptions toward the limit
    if Subscription.where("status = ? AND expires_at > ?", 'active', Time.current).count >= max_limit
      redirect_to new_user_subscription_path(current_user),
                  alert: "We limit the number of active subscriptions to ensure the best quality of service. Please try again later."
      return
    end

    unless Server.where(active: true).where("current_subscriptions < max_subscriptions").exists?
      redirect_to new_user_subscription_path(current_user),
                  alert: "No servers are available at the moment. Please try again later."
      return
    end

    subscription_name = loop do
      random_name = SecureRandom.alphanumeric(6).upcase
      break random_name unless Subscription.exists?(name: random_name)
    end

    Rails.logger.info "Creating subscription: #{subscription_name}"

    server = Server.where(active: true)
                  .where("current_subscriptions < max_subscriptions")
                  .order(:current_subscriptions)
                  .first

    expires_at = case selected_plan.interval
                when 'week'  then 1.week.from_now
                when 'month' then 1.month.from_now
                when 'year'  then 1.year.from_now
                else 1.month.from_now
    end

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
      server.increment!(:current_subscriptions)
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
    @subscription = current_user.subscriptions.find_by!(name: params[:id]) # params[:id] will be the name
    @wireguard_clients = @subscription.wireguard_clients
    @wireguard_client = @wireguard_clients.first if @wireguard_clients.any?
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan_id, :price)
  end

  def set_subscription
    @subscription = Subscription.find_by!(name: params[:id])
  end

  def authorize_subscription
    unless @subscription.user == current_user && (@subscription.active? || @subscription.pending?)
      redirect_to root_path, alert: "You do not have access to this subscription. Either it does not belong to you or it is not active."
    end
  end
end
