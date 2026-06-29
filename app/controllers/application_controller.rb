class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :authenticate_user!
  before_action :set_locale

  def authenticate_admin!
    authenticate_user!
    unless current_user.admin?
      redirect_to root_path, alert: t('flash.not_authorized')
    end
  end

  def after_sign_in_path_for(resource)
    dashboard_path
  end

  private

  def set_locale
    # Priority: 1) URL param, 2) session, 3) browser preference, 4) default (fr)
    if params[:locale].present? && I18n.available_locales.map(&:to_s).include?(params[:locale])
      session[:locale] = params[:locale]
    end

    I18n.locale = session[:locale] || extract_locale_from_accept_language_header || I18n.default_locale
  end

  def extract_locale_from_accept_language_header
    return nil unless request.env['HTTP_ACCEPT_LANGUAGE'].present?

    browser_locale = request.env['HTTP_ACCEPT_LANGUAGE']
      .scan(/[a-z]{2}/)
      .first

    return browser_locale.to_sym if I18n.available_locales.include?(browser_locale&.to_sym)
    nil
  end

  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end
end
