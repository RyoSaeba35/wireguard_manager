class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :timeoutable,
         :trackable, :jwt_authenticatable,
         jwt_revocation_strategy: JwtDenylist

  # Association with WireguardClient
  # has_many :wireguard_clients, dependent: :destroy
  has_many :refresh_tokens, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :wireguard_clients, through: :subscriptions
  has_many :shadowsocks_clients, through: :subscriptions
  has_many :hysteria2_clients, through: :subscriptions
  has_many :devices, dependent: :destroy

  def generate_refresh_token
    jti = SecureRandom.uuid
    exp = 30.days.from_now

    # Store in database
    refresh_tokens.create!(jti: jti, exp: exp)

    # Encode as JWT
    JWT.encode(
      {
        jti: jti,
        sub: id,
        exp: exp.to_i,
        type: 'refresh' # Mark as refresh token
      },
      Rails.application.credentials.devise_jwt_secret_key,
      'HS256'
    )
  end

  # ⭐ Validate and consume a refresh token (one-time use)
  def consume_refresh_token(jti)
    token = refresh_tokens.find_by(jti: jti)

    if token && !token.expired?
      token.destroy # One-time use
      true
    else
      false
    end
  end

  # Clean up old refresh tokens for this user
  def cleanup_refresh_tokens
    refresh_tokens.where('exp < ?', Time.current).delete_all
  end

  # Helper method to check admin status
  def admin?
    admin # This returns the value of the `admin` column (true/false)
  end

  # Add this method to ensure the user can be deleted
  def can_be_deleted?
    # Check if this is the last admin user
    if admin && User.where(admin: true).count <= 1
      errors.add(:base, "Cannot delete the last admin user")
      return false
    end

    # Check if user has any active subscriptions
    if subscriptions.active.any?
      errors.add(:base, "User has active subscriptions")
      return false
    end

    true
  end
end
