# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :timeoutable,
         :trackable, :jwt_authenticatable,
         jwt_revocation_strategy: JwtDenylist

  has_many :refresh_tokens, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :devices, dependent: :destroy

  # NEW: Pooling associations
  has_many :vpn_connections

  # REMOVED: has_many :wireguard_clients, through: :subscriptions
  # REMOVED: has_many :shadowsocks_clients, through: :subscriptions
  # REMOVED: has_many :hysteria2_clients, through: :subscriptions

  def generate_refresh_token
    jti = SecureRandom.uuid
    exp = 30.days.from_now

    refresh_tokens.create!(jti: jti, exp: exp)

    JWT.encode(
      {
        jti: jti,
        sub: id,
        exp: exp.to_i,
        type: 'refresh'
      },
      ENV['DEVISE_JWT_SECRET_KEY'],
      'HS256'
    )
  end

  def consume_refresh_token(jti)
    token = refresh_tokens.find_by(jti: jti)

    if token && !token.expired?
      token.destroy
      true
    else
      false
    end
  end

  def cleanup_refresh_tokens
    refresh_tokens.where('exp < ?', Time.current).delete_all
  end

  def admin?
    admin
  end

  def can_be_deleted?
    if admin && User.where(admin: true).count <= 1
      errors.add(:base, "Cannot delete the last admin user")
      return false
    end

    if subscriptions.active.any?
      errors.add(:base, "User has active subscriptions")
      return false
    end

    true
  end
end
