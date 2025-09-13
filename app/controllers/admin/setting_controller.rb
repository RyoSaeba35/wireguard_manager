# app/controllers/admin/setting_controller.rb
module Admin
  class SettingController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    def edit
      @setting = Setting.find_or_initialize_by(key: 'max_active_subscriptions')
    end

    def update
      @setting = Setting.find_by(key: 'max_active_subscriptions')
      if @setting.update(value: params[:setting][:value])
        redirect_to admin_dashboard_index_path, notice: 'Limit updated successfully.'
      else
        render :edit, alert: 'Failed to update limit.'
      end
    end

    private

    def require_admin!
      unless current_user.admin?
        redirect_to root_path, alert: "You are not authorized to access this page."
      end
    end
  end
end
