class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_subscription, only: [:show, :cancel]
  before_action :authorize_subscription, only: [:show, :cancel]

  def new
    if current_user.subscriptions.where("status = ? AND expires_at > ?", "active", Time.current).exists?
      existing = current_user.subscriptions.where("status = ? AND expires_at > ?", "active", Time.current).first
      redirect_to user_subscription_path(current_user, existing),
                  alert: "You already have an active subscription to #{existing.plan.name}."
      return
    end

    if current_user.subscriptions.where(status: ["pending", "payment_pending"]).exists?
      pending = current_user.subscriptions.where(status: ["pending", "payment_pending"]).order(created_at: :desc).first
      redirect_to user_subscription_path(current_user, pending),
                  notice: "You already have a pending subscription."
      return
    end

    @plans = Plan.all.order(:price)
    @subscription = current_user.subscriptions.new
  end

  def create_checkout_session
    @subscription = current_user.subscriptions.find(params[:subscription_id])
    service = StripeCheckoutService.new(@subscription)
    session = service.create_session
    render json: { url: session.url }
  end

  def create
    selected_plan = Plan.find(subscription_params[:plan_id])

    if Subscription.where("status = ? AND expires_at > ?", "active", Time.current).count >= Setting.max_active_subscriptions
      redirect_to new_user_subscription_path(current_user),
                  alert: "We limit active subscriptions to ensure the best quality of service. Please try again later."
      return
    end

    if current_user.subscriptions.where(status: ["pending", "payment_pending"]).exists?
      pending = current_user.subscriptions.where(status: ["pending", "payment_pending"]).order(created_at: :desc).first
      redirect_to user_subscription_path(current_user, pending),
                  notice: "You already have a pending subscription."
      return
    end

    server = Server.where(active: true)
                   .where("current_subscriptions < max_subscriptions")
                   .order(:current_subscriptions)
                   .first

    unless server
      redirect_to new_user_subscription_path(current_user),
                  alert: "No servers are available at the moment. Please try again later."
      return
    end

    expires_at = case selected_plan.interval
                 when "week"  then 1.week.from_now + 2.hours
                 when "month" then 1.month.from_now + 2.hours
                 when "year"  then 1.year.from_now + 2.hours
                 else 1.month.from_now + 2.hours
    end

    # Always use preallocated — never create on-demand without clients
    preallocated = server.subscriptions.preallocated.first

    unless preallocated
      redirect_to new_user_subscription_path(current_user),
                  alert: "No subscriptions are available at the moment. Please try again shortly."
      return
    end

    preallocated.update!(
      user_id: current_user.id,
      status: "payment_pending",
      plan_id: selected_plan.id,
      price: selected_plan.price,
      expires_at: expires_at
    )

    @subscription = preallocated
    server.increment!(:current_subscriptions)

    # Reuse existing open Stripe session if available
    if @subscription.stripe_session_id.present?
      begin
        session = Stripe::Checkout::Session.retrieve(@subscription.stripe_session_id)
        if session.status == "open"
          redirect_to session.url, status: 303, allow_other_host: true
          return
        end
      rescue Stripe::InvalidRequestError
        # Session invalid — create a new one below
      end
    end

    session = StripeCheckoutService.new(@subscription).create_session
    @subscription.update!(stripe_session_id: session.id)

    redirect_to session.url, status: 303, allow_other_host: true
  end

  def show
    # Handle payment_pending state
    if @subscription.payment_pending? && @subscription.stripe_session_id.present?
      begin
        session = Stripe::Checkout::Session.retrieve(@subscription.stripe_session_id)

        case session.status
        when "open"
          @pending_payment = true
          @stripe_session_url = session.url
        when "complete"
          @subscription.update!(status: "pending")
          redirect_to user_subscription_path(current_user, @subscription),
                      notice: "Your payment was successful."
          return
        else
          # Session expired or canceled — return to pool
          return_to_pool(@subscription)
          redirect_to new_user_subscription_path(current_user),
                      notice: "Your session has expired. Please create a new subscription."
          return
        end
      rescue Stripe::InvalidRequestError
        return_to_pool(@subscription)
        redirect_to new_user_subscription_path(current_user),
                    notice: "Your session has expired. Please create a new subscription."
        return
      end
    end

    @wireguard_clients = @subscription.wireguard_clients.order(:name)
    @wireguard_client = @wireguard_clients.first if @wireguard_clients.any?
  end

  def cancel
    unless @subscription.payment_pending?
      redirect_to root_path, alert: "This subscription cannot be cancelled."
      return
    end

    StripeSessionExpirer.expire(@subscription)
    return_to_pool(@subscription)

    redirect_to new_user_subscription_path(current_user),
                notice: "Your subscription has been canceled."
  end

  private

  def return_to_pool(subscription)
    subscription.update!(
      user_id: nil,
      status: "preallocated",
      stripe_session_id: nil
    )
    Rails.logger.info "Returned subscription #{subscription.name} to preallocated pool"
  end

  def subscription_params
    params.require(:subscription).permit(:plan_id, :price)
  end

  def set_subscription
    @subscription = current_user.subscriptions.find_by(name: params[:id])
    redirect_to root_path, alert: "Subscription not found." unless @subscription
  end

  def authorize_subscription
    unless @subscription.user == current_user &&
           (@subscription.active? || @subscription.pending? ||
            @subscription.payment_pending? || @subscription.expired?)
      redirect_to root_path, alert: "You do not have access to this subscription."
    end
  end
end
