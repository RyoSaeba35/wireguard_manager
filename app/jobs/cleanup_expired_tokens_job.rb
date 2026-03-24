# app/jobs/cleanup_expired_tokens_job.rb
class CleanupExpiredTokensJob < ApplicationJob
  queue_as :default

  def perform
    RefreshToken.cleanup_expired
    JwtDenylist.where('exp < ?', Time.current).delete_all
  end
end
