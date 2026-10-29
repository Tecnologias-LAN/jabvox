# frozen_string_literal: true

class Jabvox::StorageUsageService
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

  # Panel de "Uso del plan": muestra el consumo TOTAL (mensajes + tickets + Drive).
  def call
    used = usage_by_category(include_drive: true)
    total = used.values.sum
    quota = account.storage_quota_bytes

    {
      quota_bytes: quota,
      quota_gb: bytes_to_gb(quota),
      used_bytes: total,
      used_gb: bytes_to_gb(total),
      available_bytes: quota.positive? ? [quota - total, 0].max : nil,
      percent_used: quota.positive? ? ((total.to_f / quota) * 100).round(2) : nil,
      by_type: used.transform_values { |bytes| { bytes: bytes, gb: bytes_to_gb(bytes) } },
      trash_bytes: drive_trash_bytes,
      trash_gb: bytes_to_gb(drive_trash_bytes)
    }
  end

  # Uso que cuenta contra el límite al ADMITIR un adjunto de mensaje entrante
  # (Attachment#within_account_storage_limit → storage_over_quota?). Aquí NO se
  # incluye el Drive A PROPÓSITO: el Drive tiene su propio mecanismo de overflow
  # (los entrantes que no caben van a un bucket de excedentes, nunca se pierden),
  # así que contar el Drive aquí rechazaría mensajes entrantes y rompería la
  # mensajería. El consumo del Drive se controla con su contador atómico propio
  # (QuotaService) en las subidas manuales, no con esta validación.
  def total_bytes
    usage_by_category(include_drive: false).values.sum
  end

  def total_gb
    bytes_to_gb(total_bytes)
  end

  private

  def usage_by_category(include_drive: true)
    cache_key = include_drive ? :with_drive : :without_drive
    (@usage_cache ||= {})[cache_key] ||= compute_usage(include_drive: include_drive)
  end

  def compute_usage(include_drive:)
    rows = attachment_scope
           .joins(file_attachment: :blob)
           .group(:file_type)
           .sum('active_storage_blobs.byte_size')

    message_usage = CATEGORIES.transform_values { |file_type| rows[Attachment.file_types[file_type]].to_i }
    usages = [message_usage, ticket_usage_by_category]
    usages << drive_usage_by_category if include_drive
    merge_usage(*usages)
  end

  # Uso de jabvox-drive por categoría. El Drive es la fuente canónica del consumo
  # de espacio del plan. Cuenta lo que OCUPA cuota: archivos activos Y los que están
  # en la PAPELERA (siguen ocupando hasta que se eliminen definitivamente). Solo los
  # PURGADOS dejan de contar. (occupying_quota = no purgados.)
  def drive_usage_by_category
    return CATEGORIES.keys.index_with { 0 } unless drive_enabled?

    rows = account.jabvox_drive_files.occupying_quota
                  .group(drive_category_sql)
                  .sum(:byte_size)

    CATEGORIES.keys.index_with { |key| rows[key.to_s].to_i }
  end

  # Bytes actualmente en la PAPELERA (para mostrarlo aparte en el panel).
  def drive_trash_bytes
    return 0 unless drive_enabled?

    account.jabvox_drive_files.in_trash.sum(:byte_size)
  end

  def drive_enabled?
    account.respond_to?(:jabvox_drive_enabled_jabvox?) && account.jabvox_drive_enabled_jabvox?
  end

  def drive_category_sql
    Arel.sql(<<~SQL.squish)
      CASE
      WHEN content_type LIKE 'image/%' THEN 'images'
      WHEN content_type LIKE 'video/%' THEN 'videos'
      WHEN content_type LIKE 'audio/%' THEN 'audios'
      ELSE 'documents'
      END
    SQL
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
