class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Association with WireguardClient
  has_many :wireguard_clients, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
end
