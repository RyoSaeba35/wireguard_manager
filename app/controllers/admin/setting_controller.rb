# app/controllers/admin/setting_controller.rb
module Admin
  class SettingController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :set_setting

    def edit
      # System capacity metrics
      @total_capacity = Server.active.where(healthy: true).sum(:max_concurrent_connections)
      @active_connections = VpnConfigSet.where(status: 'in_use').count
      @capacity_percent = @total_capacity > 0 ? (@active_connections.to_f / @total_capacity * 100).round(1) : 0

      # Pool metrics
      @total_configs = VpnConfigSet.count
      @available_configs = VpnConfigSet.where(status: 'available').count
      @in_use_configs = VpnConfigSet.where(status: 'in_use').count
      @used_configs = VpnConfigSet.where(status: 'used').count

      # Server health
      @total_servers = Server.active.count
      @healthy_servers = Server.active.where(healthy: true).count

      # Subscription metrics
      @active_subscriptions = Subscription.active.count
      @total_users = User.count
      @active_users = User.joins(:subscriptions).where(subscriptions: { status: 'active' }).distinct.count
    end

    def update
      if @setting.update(setting_params)
        handle_setting_changes
        redirect_to edit_admin_setting_path, notice: "Settings updated successfully."
      else
        load_metrics
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_setting
      @setting = SystemSetting.instance  # ⭐ CHANGED
    end

    def require_admin
      unless current_user.admin?
        redirect_to root_path, alert: "Access denied."
      end
    end

    def setting_params
      params.require(:system_setting).permit(  # ⭐ CHANGED
        :maintenance_mode,
        :allow_new_registrations,
        :max_devices_per_user,
        :session_timeout_minutes,
        :pool_recycle_hour,
        :credential_rotation_enabled,
        :enable_email_notifications,
        :smtp_host,
        :smtp_port,
        :smtp_username,
        :smtp_password,
        :support_email,
        :company_name
      )
    end

    def handle_setting_changes
      if @setting.saved_change_to_maintenance_mode?
        Rails.logger.info @setting.maintenance_mode? ? "Maintenance mode enabled" : "Maintenance mode disabled"
      end

      if @setting.saved_change_to_pool_recycle_hour?
        Rails.logger.info "Pool recycle hour updated to #{@setting.pool_recycle_hour}:00"
      end
    end

    def load_metrics
      @total_capacity = Server.active.where(healthy: true).sum(:max_concurrent_connections)
      @active_connections = VpnConfigSet.where(status: 'in_use').count
      @capacity_percent = @total_capacity > 0 ? (@active_connections.to_f / @total_capacity * 100).round(1) : 0
      @total_configs = VpnConfigSet.count
      @available_configs = VpnConfigSet.where(status: 'available').count
      @in_use_configs = VpnConfigSet.where(status: 'in_use').count
      @used_configs = VpnConfigSet.where(status: 'used').count
      @total_servers = Server.active.count
      @healthy_servers = Server.active.where(healthy: true).count
      @active_subscriptions = Subscription.active.count
      @total_users = User.count
      @active_users = User.joins(:subscriptions).where(subscriptions: { status: 'active' }).distinct.count
    end
  end
end
