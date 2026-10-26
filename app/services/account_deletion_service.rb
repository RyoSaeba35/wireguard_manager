# app/services/account_deletion_service.rb
#
# Deletes a user and everything tied to them, in the order the foreign keys
# require. A plain `user.destroy` fails as soon as the user has VPN history:
# vpn_connections and vpn_config_sets both point at devices, and
# vpn_connections also points at users, with no `dependent:` on those.
#
# Subscriptions are detached (user_id = nil) instead of deleted: they hold no
# personal data once detached, and keep payment history consistent with
# Stripe for accounting. Active ones are expired so they free their slots.
#
# Used by both DELETE /api/account and the website "Delete my account" button.
class AccountDeletionService
  def initialize(user)
    @user = user
  end

  def call!
    user_id = @user.id
    email = @user.email

    ActiveRecord::Base.transaction do
      device_ids = @user.devices.pluck(:id)

      # 1. Give in-use configs back to the pool (RecycleConfigsJob recycles them)
      VpnConfigSet.where(device_id: device_ids, status: "in_use").find_each(&:release!)
      VpnConfigSet.where(device_id: device_ids).update_all(device_id: nil)

      # 2. Connection history (FK to users and devices)
      VpnConnection.where(user_id: user_id).delete_all
      VpnConnection.where(device_id: device_ids).delete_all

      # 3. Devices
      Device.where(id: device_ids).delete_all

      # 4. Subscriptions: expire active ones, then detach all from the user
      @user.subscriptions.where(status: "active").update_all(
        status: "expired", expires_at: Time.current, updated_at: Time.current
      )
      @user.subscriptions.update_all(user_id: nil, updated_at: Time.current)

      # 5. Sessions
      @user.refresh_tokens.delete_all

      # 6. The user itself
      @user.reload.destroy!
    end

    Rails.logger.info "[AccountDeletion] Deleted user #{user_id} (#{email})"
    true
  end
end
