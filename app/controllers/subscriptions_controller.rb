# app/controllers/subscriptions_controller.rb
class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_subscription, only: [:show, :cancel]
  before_action :authorize_subscription, only: [:show, :cancel]

  def new
    # Check for existing active subscription
    if current_user.subscriptions.active.exists?
      existing = current_user.subscriptions.active.first
      redirect_to user_subscription_path(current_user, existing),
                  alert: "You already have an active subscription to #{existing.plan.name}."
      return
    end

    # Check for pending payment
    if current_user.subscriptions.where(status: ["pending", "payment_pending"]).exists?
      pending = current_user.subscriptions.where(status: ["pending", "payment_pending"]).order(created_at: :desc).first
      redirect_to user_subscription_path(current_user, pending),
                  notice: "You already have a pending subscription."
      return
    end

    @plans = Plan.all.order(:price)
    @subscription = current_user.subscriptions.new

    # ⭐ FIXED: Rename to match view expectation
    @pool_available = SystemSetting.can_accept_new_subscription?
  end

  def create
    # Only active plans can be bought: a deactivated plan (e.g. an old price)
    # must not be purchasable by sending its id directly.
    selected_plan = Plan.active.find_by(id: subscription_params[:plan_id])
    unless selected_plan
      redirect_to new_user_subscription_path(current_user),
                  alert: "This plan is no longer available. Please choose another one."
      return
    end

    # ⭐ NEW: Check global capacity
    unless SystemSetting.can_accept_new_subscription?
      redirect_to new_user_subscription_path(current_user),
                  alert: "We've reached capacity to ensure the best experience. New subscriptions will be available soon."
      return
    end

    # Check for pending subscription
    if current_user.subscriptions.where(status: ["pending", "payment_pending"]).exists?
      pending = current_user.subscriptions.where(status: ["pending", "payment_pending"]).order(created_at: :desc).first
      redirect_to user_subscription_path(current_user, pending),
                  notice: "You already have a pending subscription."
      return
    end

    # Provisional expiry (the column is required). Subscription#activate!
    # resets it from the moment payment completes.
    expires_at = Subscription.expiry_from(selected_plan.interval)

    # Generate unique subscription name
    subscription_name = loop do
      name = SecureRandom.alphanumeric(5).upcase
      break name unless Subscription.exists?(name: name)
    end

    @subscription = current_user.subscriptions.create!(
      name: subscription_name,
      status: "payment_pending",
      plan: selected_plan,
      price: selected_plan.price,
      expires_at: expires_at,
      max_devices: 3
    )

    # Create Stripe checkout session
    session = StripeCheckoutService.new(@subscription).create_session
    @subscription.update!(stripe_session_id: session.id)

    redirect_to session.url, allow_other_host: true
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
          @subscription.activate!
          redirect_to user_subscription_path(current_user, @subscription),
                      notice: "Your payment was successful! You can now connect your devices."
          return
        else
          # Session expired or canceled
          @subscription.update!(status: "failed")
          redirect_to new_user_subscription_path(current_user),
                      notice: "Your session has expired. Please create a new subscription."
          return
        end
      rescue Stripe::InvalidRequestError
        @subscription.update!(status: "failed")
        redirect_to new_user_subscription_path(current_user),
                    notice: "Your session has expired. Please create a new subscription."
        return
      end
    end

    # ⭐ NEW: Show devices and connections (no downloadable configs)
    all_devices = @subscription.devices.order(created_at: :desc).to_a
    @active_connections = @subscription.vpn_connections.active.includes(:server, :device)
    @recent_connections = @subscription.vpn_connections.completed.order(disconnected_at: :desc).limit(10)

    # Sort devices: connected first, then disconnected
    connected_device_ids = @active_connections.map(&:device_id)
    @devices = all_devices.partition { |d| connected_device_ids.include?(d.id) }.flatten
  end

  def cancel
    unless @subscription.payment_pending?
      redirect_to root_path, alert: "This subscription cannot be cancelled."
      return
    end

    # Expire Stripe session
    StripeSessionExpirer.expire(@subscription)

    # Mark as failed
    @subscription.update!(status: "failed", stripe_session_id: nil)

    redirect_to new_user_subscription_path(current_user),
                notice: "Your subscription has been canceled."
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan_id)
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
