# Removes expired durable query-cache rows. Scheduled via config/schedule.yml.
class Jabvox::Analytics::CacheSweeperJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JabvoxAnalyticsQueryCacheEntry.expired.in_batches(of: 1000).delete_all
  end
end
