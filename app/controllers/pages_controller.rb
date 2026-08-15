class PagesController < ApplicationController
  before_action :authenticate_user!, only: [:subscriptions_expired]
  skip_before_action :authenticate_user!, only: [
    :privacy,
    :terms,
    :logging,
    :blog,
    :vpn_expats_france,
    :vpn_france_logs,
    :vpn_voyage,
    :vpn_vie_privee,
    :vpn_vs_grands,
    :vpn_teletravail,
    :vpn_android
  ]

  def privacy
  end

  def terms
  end

  def logging
  end

  def blog
  end

  def vpn_expats_france
  end

  def vpn_france_logs
  end

  def vpn_voyage
  end

  def vpn_vie_privee
  end

  def vpn_vs_grands
  end

  def vpn_teletravail
  end

  def vpn_android
  end

  def subscriptions_expired
    @expired_subscriptions = current_user.subscriptions.expired.order(expires_at: :desc)
  end
end
