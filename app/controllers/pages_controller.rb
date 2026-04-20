class PagesController < ApplicationController
  before_action :authenticate_user!, only: [:subscriptions_expired]
  skip_before_action :authenticate_user!, only: [:privacy, :terms, :logging]

  def privacy
  end

  def terms
  end

  def logging
  end

  def subscriptions_expired
    @expired_subscriptions = current_user.subscriptions.expired.order(expires_at: :desc)
  end
end
