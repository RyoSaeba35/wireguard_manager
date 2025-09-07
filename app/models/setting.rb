# app/models/setting.rb
class Setting < ApplicationRecord
  def self.max_active_subscriptions
    # Return the sum of all active servers' max_subscriptions
    Server.where(active: true).sum(:max_subscriptions)
  rescue ActiveRecord::StatementInvalid
    # Fallback to a default value if there's an error (e.g., no servers table)
    5
  end
end
