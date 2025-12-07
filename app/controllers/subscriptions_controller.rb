class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_subscription, only: [:show]
  before_action :authorize_subscription, only: [:show]

  def new
    # Check for active subscriptions
    if current_user.subscriptions.where("status IN (?) AND expires_at > ?", ['active'], Time.current).exists?
      existing_subscription = current_user.subscriptions.where("status IN (?) AND expires_at > ?", ['active'], Time.current).first
      redirect_to user_subscription_path(current_user, existing_subscription),
                  alert: "You already have an active subscription to #{existing_subscription.plan.name}."
      return
    end

    # Check for pending subscriptions
    if current_user.subscriptions.where(status: ['pending', 'payment_pending']).exists?
      pending_subscription = current_user.subscriptions.where(status: ['pending', 'payment_pending']).order(created_at: :desc).first
      redirect_to user_subscription_path(current_user, pending_subscription),
                  notice: "You already have a pending subscription."
      return
    end

    @plans = Plan.all.order(:price)
    @subscription = current_user.subscriptions.new
  end

  # POST /users/:user_id/subscriptions/:subscription_id/create_checkout_session
  def create_checkout_session
    @subscription = current_user.subscriptions.find(params[:subscription_id])
    service = StripeCheckoutService.new(@subscription)
    session = service.create_session

    render json: { url: session.url }
  end

  # POST /users/:user_id/subscriptions
  def create
    selected_plan = Plan.find(subscription_params[:plan_id])

    # Check max active subscriptions
    if Subscription.where("status = ? AND expires_at > ?", 'active', Time.current).count >= Setting.max_active_subscriptions
      redirect_to new_user_subscription_path(current_user),
                  alert: "We limit active subscriptions to ensure the best quality of service. Please try again later."
      return
    end

    # Check for payment_pending subscriptions
    if current_user.subscriptions.where(status: 'payment_pending').exists?
      pending_subscription = current_user.subscriptions.where(status: 'payment_pending').order(created_at: :desc).first
      redirect_to user_subscription_path(current_user, pending_subscription),
                  notice: "You already have a pending subscription. Please complete your payment."
      return
    end

    # Check for pending subscriptions
    if current_user.subscriptions.where(status: 'pending').exists?
      pending_subscription = current_user.subscriptions.where(status:'pending').order(created_at: :desc).first
      redirect_to user_subscription_path(current_user, pending_subscription),
                  notice: "You already have a pending subscription."
      return
    end

    # Check available servers
    server = Server.where(active: true).where("current_subscriptions < max_subscriptions").order(:current_subscriptions).first
    unless server
      redirect_to new_user_subscription_path(current_user),
                  alert: "No servers are available at the moment. Please try again later."
      return
    end

    # Calculate expires_at
    expires_at = case selected_plan.interval
                 when 'week'  then (1.week.from_now + 2.hours)
                 when 'month' then (1.month.from_now + 2.hours)
                 when 'year'  then (1.year.from_now + 2.hours)
                 else (1.month.from_now + 2.hours)
    end

    # Try preallocated subscription
    preallocated_subscription = server.subscriptions.preallocated.first

    if preallocated_subscription
      preallocated_subscription.update!(
        user_id: current_user.id,
        status: 'payment_pending', # pending until Stripe payment completes
        plan_id: selected_plan.id,
        price: selected_plan.price,
        expires_at: expires_at
      )

      @subscription = preallocated_subscription
    else
      # On-demand subscription
      subscription_name = loop do
        random_name = SecureRandom.alphanumeric(5).upcase
        break random_name unless Subscription.exists?(name: random_name)
      end

      @subscription = current_user.subscriptions.new(
        subscription_params.merge(
          name: subscription_name,
          status: 'payment_pending', # pending until Stripe payment completes
          server: server,
          expires_at: expires_at,
          plan: selected_plan
        )
      )

      unless @subscription.save
        Rails.logger.error "Failed to create subscription: #{@subscription.errors.full_messages.join(', ')}"
        @plans = Plan.all
        render :new, status: :unprocessable_entity
        return
      end
    end

    server.increment!(:current_subscriptions)

    # Check if the subscription already has a Stripe session
    if @subscription.stripe_session_id.present?
      begin
        session = Stripe::Checkout::Session.retrieve(@subscription.stripe_session_id)

        # If the session is still open, reuse it
        if session.status == 'open'
          redirect_to session.url, status: 303, allow_other_host: true
          return
        end
      rescue Stripe::InvalidRequestError
        # Session doesn't exist or is invalid
      end
    end

    # Create Stripe Checkout session
    service = StripeCheckoutService.new(@subscription)
    session = service.create_session
    @subscription.update!(stripe_session_id: session.id)

    # Redirect user to Stripe Checkout
    redirect_to session.url, status: 303, allow_other_host: true
  end

  def show
    @subscription = current_user.subscriptions.find_by!(name: params[:id])

    # If the subscription is payment_pending and the Stripe session is still open or complete
    if @subscription.payment_pending? && @subscription.stripe_session_id.present?
      begin
        session = Stripe::Checkout::Session.retrieve(@subscription.stripe_session_id)

        case session.status
        when 'open'
          @pending_payment = true
          @stripe_session_url = session.url
        when 'complete'
          # Payment was successful, activate the subscription
          @subscription.update!(status: 'pending')
          redirect_to user_subscription_path(current_user, @subscription), notice: "Your payment was successful."
          return
        else
          # If the session is expired or in any other state, mark subscription as canceled
          @subscription.update!(status: 'canceled')
          redirect_to new_user_subscription_path(current_user), notice: "Your session has expired. Please create a new subscription."
          return
        end
      rescue Stripe::InvalidRequestError
        # If the session is invalid, mark the subscription as canceled
        @subscription.update!(status: 'canceled')
        redirect_to new_user_subscription_path(current_user), notice: "Your session has expired. Please create a new subscription."
        return
      end
    end

    # Check if payment is still pending after 1 hour and no pending payment is detected
    if @subscription.payment_pending? && !@pending_payment && @subscription.created_at < 1.hour.ago
      begin
        session = Stripe::Checkout::Session.retrieve(@subscription.stripe_session_id)
        Stripe::Checkout::Session.expire(@subscription.stripe_session_id) if session.status == 'open'
      rescue Stripe::InvalidRequestError
        # Session is already invalid
      end
      @subscription.update!(status: 'canceled')
      redirect_to new_user_subscription_path(current_user), notice: "Your session has expired. Please create a new subscription."
      return
    end

    @wireguard_clients = @subscription.wireguard_clients.order(:name)
    @wireguard_client = @wireguard_clients.first if @wireguard_clients.any?
  end

  def cancel
    @subscription = current_user.subscriptions.find_by!(name: params[:id])

    # Enqueue the job to handle cancellation and cleanup
    CancelSubscriptionJob.perform_later(@subscription.id)

    # Wait for 1.5 seconds before redirecting
    sleep(1.5)

    redirect_to new_user_subscription_path(current_user), notice: "Your subscription has been canceled."
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan_id, :price)
  end

  def set_subscription
    @subscription = Subscription.find_by(name: params[:id])
    unless @subscription
      redirect_to root_path, alert: "Subscription not found."
    end
  end

  def authorize_subscription
    unless @subscription && @subscription.user == current_user && (@subscription.active? || @subscription.pending? || @subscription.payment_pending?)
      redirect_to root_path, alert: "You do not have access to this subscription."
    end
  end
end
