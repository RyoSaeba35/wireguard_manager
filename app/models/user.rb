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
  has_many :subscriptions, dependent: :destroy
  has_many :wireguard_clients, through: :subscriptions
  has_many :devices, dependent: :destroy

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
