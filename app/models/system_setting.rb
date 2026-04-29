# app/models/system_setting.rb (RENAME from setting.rb)
class SystemSetting < ApplicationRecord
  # ==========================================
  # VALIDATIONS
  # ==========================================
  validates :max_devices_per_user,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal: 10 }
  validates :session_timeout_minutes,
            numericality: { only_integer: true, greater_than: 0 }
  validates :pool_recycle_hour,
            numericality: { only_integer: true, greater_than_or_equal: 0, less_than: 24 }
  validates :support_email,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            allow_blank: true

  # ==========================================
  # SINGLETON PATTERN
  # ==========================================
  def self.instance
    first_or_create!(
      maintenance_mode: false,
      allow_new_registrations: true,
      max_devices_per_user: 3,
      session_timeout_minutes: 1440,
      pool_recycle_hour: 3,
      credential_rotation_enabled: true
    )
  rescue ActiveRecord::RecordInvalid
    first
  end

  # ==========================================
  # CAPACITY CALCULATIONS (Pool-Based)
  # ==========================================

  def self.can_accept_new_subscription?
    setting = instance

    return false if setting.maintenance_mode?
    return false unless setting.allow_new_registrations?

    available_configs = VpnConfigSet.where(status: 'available').count

    # Simple: ensure you can handle 20 simultaneous signups
    # (20 subs × 3 devices = 60 configs)
    min_buffer = 50 * max_devices_per_user

    available_configs >= min_buffer
  end

  def self.max_active_subscriptions
    total_connections = Server.active.where(healthy: true).sum(:max_concurrent_connections)
    max_devices = instance.max_devices_per_user || 3
    max_subs = total_connections / max_devices
    safe_limit = (max_subs * 1.0).to_i
    safe_limit
  rescue ActiveRecord::StatementInvalid, NoMethodError
    5
  end

  def self.current_subscriptions
    Subscription.active.count
  rescue ActiveRecord::StatementInvalid
    0
  end

  def self.current_connections
    VpnConfigSet.where(status: 'in_use').count
  rescue ActiveRecord::StatementInvalid
    0
  end

  def self.total_capacity
    Server.active.where(healthy: true).sum(:max_concurrent_connections)
  rescue ActiveRecord::StatementInvalid
    0
  end

  def self.capacity_stats
    servers = Server.active.where(healthy: true)
    total_connections = servers.sum(:max_concurrent_connections)
    max_devices = instance.max_devices_per_user || 3

    active_connections = VpnConfigSet.where(status: 'in_use').count
    total_configs = VpnConfigSet.count
    available_configs = VpnConfigSet.where(status: 'available').count
    in_use_configs = VpnConfigSet.where(status: 'in_use').count
    used_configs = VpnConfigSet.where(status: 'used').count

    {
      total_servers: servers.count,
      healthy_servers: servers.count,
      total_capacity: total_connections,
      max_devices_per_subscription: max_devices,
      theoretical_max_subscriptions: total_connections / max_devices,
      safe_subscription_limit: max_active_subscriptions,
      current_subscriptions: current_subscriptions,
      available_subscription_slots: [max_active_subscriptions - current_subscriptions, 0].max,
      subscription_utilization_percent: max_active_subscriptions > 0 ?
        (current_subscriptions.to_f / max_active_subscriptions * 100).round(1) : 0,

      pool: {
        total_configs: total_configs,
        available: available_configs,
        in_use: in_use_configs,
        used: used_configs,
        pool_utilization_percent: total_configs > 0 ?
          ((in_use_configs + used_configs).to_f / total_configs * 100).round(1) : 0
      },

      connections: {
        active: active_connections,
        capacity: total_connections,
        utilization_percent: total_connections > 0 ?
          (active_connections.to_f / total_connections * 100).round(1) : 0
      },

      can_accept_new: can_accept_new_subscription?,
      maintenance_mode: instance.maintenance_mode?,
      accepting_registrations: instance.allow_new_registrations?,

      servers: servers.map do |server|
        {
          id: server.id,
          name: server.name,
          location: server.location,
          max_connections: server.max_concurrent_connections,
          current_connections: server.vpn_config_sets.where(status: 'in_use').count,
          pool_size: server.config_pool_size,
          available_configs: server.vpn_config_sets.where(status: 'available').count,
          load_percent: server.max_concurrent_connections > 0 ?
            (server.vpn_config_sets.where(status: 'in_use').count.to_f / server.max_concurrent_connections * 100).round(1) : 0
        }
      end
    }
  rescue ActiveRecord::StatementInvalid, NoMethodError => e
    Rails.logger.error("Error calculating capacity stats: #{e.message}")
    {
      error: "Unable to calculate capacity stats",
      total_servers: 0,
      can_accept_new: false
    }
  end

  # ==========================================
  # INSTANCE METHODS
  # ==========================================

  def maintenance_mode?
    maintenance_mode == true
  end

  def allow_new_registrations?
    allow_new_registrations == true
  end

  def credential_rotation_enabled?
    credential_rotation_enabled == true
  end

  def email_notifications_enabled?
    enable_email_notifications == true
  end

  def pool_recycle_time
    Time.current.change(hour: pool_recycle_hour || 3, min: 0, sec: 0)
  end

  def next_pool_recycle
    recycle_time = pool_recycle_time
    recycle_time = recycle_time + 1.day if recycle_time < Time.current
    recycle_time
  end

  def system_healthy?
    !maintenance_mode? &&
    Server.active.where(healthy: true).exists? &&
    VpnConfigSet.where(status: 'available').count > 100
  end

  # ==========================================
  # CLASS HELPER METHODS
  # ==========================================

  def self.maintenance_mode?
    instance.maintenance_mode?
  rescue
    false
  end

  def self.allow_new_registrations?
    instance.allow_new_registrations?
  rescue
    true
  end

  def self.max_devices_per_user
    instance.max_devices_per_user || 3
  rescue
    3
  end
end
