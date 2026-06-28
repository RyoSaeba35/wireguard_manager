# app/models/server.rb
class Server < ApplicationRecord
  encrypts :ssh_user, :ssh_password, :ssh_private_key, deterministic: true
  encrypts :singbox_ss_master_password, :singbox_salamander_password
  encrypts :clash_api_secret

  has_many :vpn_config_sets, dependent: :destroy
  has_many :vpn_connections

  validates :name, presence: true
  validates :ip_address, presence: true
  validates :max_concurrent_connections, numericality: { only_integer: true, greater_than: 0 }
  validates :config_pool_size, numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :healthy, -> { where(healthy: true) }

  def healthy?
    healthy == true
  end

  def flag
    return nil unless country_code.present?
    country_code.upcase.chars.map { |c| (c.ord + 127397).chr(Encoding::UTF_8) }.join
  end

  def current_connections
    vpn_config_sets.where(status: 'in_use').count
  end

  def available_configs
    vpn_config_sets.where(status: 'available').count
  end

  def load_percent
    return 0 if max_concurrent_connections.zero?
    (current_connections.to_f / max_concurrent_connections * 100).round(1)
  end

  def capacity_remaining
    max_concurrent_connections - current_connections
  end

  def at_capacity?
    current_connections >= max_concurrent_connections
  end
end
