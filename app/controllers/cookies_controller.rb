class CookiesController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def accept
    cookies.permanent[:cookie_consent] = 'accepted'
    redirect_back fallback_location: root_path
  end

  def decline
    cookies.permanent[:cookie_consent] = 'declined'
    redirect_back fallback_location: root_path
  end
end
