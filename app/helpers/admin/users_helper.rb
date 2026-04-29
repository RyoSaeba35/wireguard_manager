# app/helpers/admin/users_helper.rb
module Admin
  module UsersHelper
    def active_subscriptions_count(user)
      @active_subscriptions_by_user[user.id] || 0
    end

    def expired_subscriptions_count(user)
      @expired_subscriptions_by_user[user.id] || 0
    end

    def has_active_subscription?(user)
      active_subscriptions_count(user) > 0
    end

    def user_subscriptions(user, status)
      @subscriptions_data[user.id]&.select do |sub|
        case status
        when :active
          sub.active?
        when :expired
          sub.expired?
        else
          true
        end
      end || []
    end
  end
end
