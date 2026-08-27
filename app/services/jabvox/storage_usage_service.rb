# frozen_string_literal: true

module Jabvox
  class StorageUsageService
    CATEGORIES = {
      images: 'image',
      videos: 'video',
      audios: 'audio',
      documents: 'file'
    }.freeze

    attr_reader :account

    def initialize(account)
      @account = account
    end

    def call
      used = usage_by_category
      total = used.values.sum
      quota = account.storage_quota_bytes

      {
        quota_bytes: quota,
        quota_gb: bytes_to_gb(quota),
        used_bytes: total,
        used_gb: bytes_to_gb(total),
        available_bytes: quota.positive? ? [quota - total, 0].max : nil,
        percent_used: quota.positive? ? ((total.to_f / quota) * 100).round(2) : nil,
        by_type: used.transform_values { |bytes| { bytes: bytes, gb: bytes_to_gb(bytes) } }
      }
    end

    def total_bytes
      usage_by_category.values.sum
    end

    def total_gb
      bytes_to_gb(total_bytes)
    end

    private

    def usage_by_category
      @usage_by_category ||= begin
        rows = attachment_scope
               .joins(file_attachment: :blob)
               .group(:file_type)
               .sum('active_storage_blobs.byte_size')

        message_usage = CATEGORIES.transform_values { |file_type| rows[Attachment.file_types[file_type]].to_i }
        merge_usage(message_usage, ticket_usage_by_category)
      end
    end

    def attachment_scope
      Attachment.where(account_id: account.id).where(file_type: CATEGORIES.values)
    end

    def ticket_usage_by_category
      ticket_ids = account.jabvox_tickets.select(:id)
      comment_ids = JabvoxTicketComment.where(ticket_id: ticket_ids).select(:id)
      ticket_usage = attached_usage_for('JabvoxTicket', ticket_ids)
      comment_usage = attached_usage_for('JabvoxTicketComment', comment_ids)

      merge_usage(ticket_usage, comment_usage)
    end

    def attached_usage_for(record_type, record_ids)
      rows = ActiveStorage::Attachment
             .joins(:blob)
             .where(name: 'attachments', record_type: record_type, record_id: record_ids)
             .group(Arel.sql(category_sql))
             .sum('active_storage_blobs.byte_size')

      CATEGORIES.keys.index_with { |key| rows[key.to_s].to_i }
    end

    def category_sql
      <<~SQL.squish
        CASE
        WHEN active_storage_blobs.content_type LIKE 'image/%' THEN 'images'
        WHEN active_storage_blobs.content_type LIKE 'video/%' THEN 'videos'
        WHEN active_storage_blobs.content_type LIKE 'audio/%' THEN 'audios'
        ELSE 'documents'
        END
      SQL
    end

    def merge_usage(*usages)
      CATEGORIES.keys.index_with do |key|
        usages.sum { |usage| usage[key].to_i }
      end
    end

    def bytes_to_gb(bytes)
      (bytes.to_i.to_f / 1.gigabyte).round(4)
    end
  end
end
