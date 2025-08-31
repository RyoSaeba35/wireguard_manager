class PagesController < ApplicationController
  skip_before_action :authenticate_user!

  def privacy
  end

  def terms
  end

  def logging
  end

  def subscriptions_expired
    @expired_subscriptions = Subscription.expired.order(expires_at: :desc)
  end
end
