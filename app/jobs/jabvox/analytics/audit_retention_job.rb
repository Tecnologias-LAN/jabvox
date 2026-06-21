# Prunes Analytics audit logs older than the retention window. Scheduled via config/schedule.yml.
class Jabvox::Analytics::AuditRetentionJob < ApplicationJob
  queue_as :scheduled_jobs

  RETENTION = 1.year

  def perform
    JabvoxAnalyticsAuditLog.where(created_at: ..RETENTION.ago).in_batches(of: 5000).delete_all
  end
end
