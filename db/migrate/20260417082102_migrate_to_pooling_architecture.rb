# db/migrate/YYYYMMDD_migrate_to_pooling_architecture.rb
class MigrateToPoolingArchitecture < ActiveRecord::Migration[7.2]
  def up
    # ========================================
    # 1. UPDATE SUBSCRIPTIONS
    # ========================================

    # Add max_devices
    add_column :subscriptions, :max_devices, :integer, default: 3

    # Remove server lock
    remove_foreign_key :subscriptions, :servers if foreign_key_exists?(:subscriptions, :servers)
    remove_column :subscriptions, :server_id, :integer

    # Add index for performance
    add_index :subscriptions, :status

    # ========================================
    # 2. UPDATE SERVERS
    # ========================================

    # Remove old capacity fields
    remove_column :servers, :max_subscriptions, :integer
    remove_column :servers, :current_subscriptions, :integer

    # Add new capacity fields
    add_column :servers, :max_concurrent_connections, :integer, default: 225
    add_column :servers, :config_pool_size, :integer, default: 3000

    # Add location fields
    add_column :servers, :location, :string
    add_column :servers, :city, :string
    add_column :servers, :country_code, :string
    add_column :servers, :latitude, :decimal, precision: 10, scale: 6
    add_column :servers, :longitude, :decimal, precision: 10, scale: 6

    # Add health monitoring
    add_column :servers, :healthy, :boolean, default: true
    add_column :servers, :last_health_check, :datetime
    add_column :servers, :health_failures, :integer, default: 0

    # ========================================
    # 3. CREATE VPN_CONFIG_SETS
    # ========================================

    create_table :vpn_config_sets do |t|
      # Server association
      t.references :server, null: false, foreign_key: true

      # IP address (never changes, reused daily)
      t.string :ip_address, null: false

      # WireGuard credentials (rotated daily)
      t.text :wireguard_private_key
      t.text :wireguard_public_key
      t.text :wireguard_preshared_key

      # Hysteria2 credentials (rotated daily)
      t.string :hysteria2_password

      # Shadowsocks credentials (rotated daily)
      t.string :shadowsocks_password

      # Pool status
      t.string :status, default: 'available', null: false
      # Statuses: 'available', 'in_use', 'used', 'recycling'

      # Current assignment (when in_use)
      t.references :device, foreign_key: true

      # Tracking
      t.datetime :last_rotated_at
      t.datetime :last_used_at
      t.datetime :claimed_at

      t.timestamps
    end

    # Indexes for performance
    add_index :vpn_config_sets, [:server_id, :status]
    add_index :vpn_config_sets, [:status, :updated_at]
    add_index :vpn_config_sets, :ip_address, unique: true

    # ========================================
    # 4. CREATE VPN_CONNECTIONS (Audit Log)
    # ========================================

    create_table :vpn_connections do |t|
      # Who and where
      t.references :user, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.references :config_set, null: false, foreign_key: { to_table: :vpn_config_sets }
      t.references :server, null: false, foreign_key: true

      # Connection timing
      t.datetime :connected_at, null: false
      t.datetime :disconnected_at

      # Usage tracking (optional - for future analytics)
      t.bigint :bytes_sent
      t.bigint :bytes_received

      t.timestamps
    end

    # Indexes
    add_index :vpn_connections, :connected_at
    add_index :vpn_connections, [:user_id, :connected_at]
    add_index :vpn_connections, [:device_id, :connected_at]

    # ========================================
    # 5. DELETE OLD CLIENT TABLES
    # ========================================

    drop_table :wireguard_clients
    drop_table :hysteria2_clients
    drop_table :shadowsocks_clients
  end

  def down
    # This migration is not easily reversible
    raise ActiveRecord::IrreversibleMigration
  end
end
