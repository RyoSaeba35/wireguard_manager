# db/migrate/YYYYMMDDHHMMSS_create_system_settings.rb
class CreateSystemSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :system_settings do |t|
      # System settings
      t.boolean :maintenance_mode, default: false, null: false
      t.boolean :allow_new_registrations, default: true, null: false

      # User limits
      t.integer :max_devices_per_user, default: 3, null: false
      t.integer :session_timeout_minutes, default: 1440, null: false

      # Pool management
      t.integer :pool_recycle_hour, default: 3, null: false
      t.boolean :credential_rotation_enabled, default: true, null: false

      # Email settings
      t.boolean :enable_email_notifications, default: false
      t.string :smtp_host
      t.integer :smtp_port
      t.string :smtp_username
      t.string :smtp_password
      t.string :support_email

      # Branding
      t.string :company_name, default: "VulcainVPN"

      t.timestamps
    end

    # Create the initial record
    SystemSetting.create!(
      maintenance_mode: false,
      allow_new_registrations: true,
      max_devices_per_user: 3,
      session_timeout_minutes: 1440,
      pool_recycle_hour: 3,
      credential_rotation_enabled: true,
      company_name: "VulcainVPN"
    )
  end
end
