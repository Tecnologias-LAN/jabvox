# Scheduled safety net: deletes expired short-lived access tokens (those with a non-null
# expires_at in the past). Regular tokens (expires_at IS NULL) are never touched. Backs up the
# per-token cleanup job in case one was missed.
class Jabvox::ExpiredAccessTokensSweeperJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    AccessToken.expired.in_batches(of: 500).destroy_all
  end
end
