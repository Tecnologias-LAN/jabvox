# Breaks messages down by media type (text / image / video / audio / document /
# location) for both directions. WhatsApp media arrives as an Attachment whose
# file_type carries the kind; a message with no attachment is plain text. Split
# out of the builder to keep it focused.
module V2::Reports::WhatsappReport::MessageTypeBreakdown
  # Report key => attachment file_type enum name. 'file' surfaces as "document".
  MEDIA_FILE_TYPES = { image: 'image', video: 'video', audio: 'audio',
                       document: 'file', location: 'location' }.freeze

  # Counts by type for a given message scope: { text:, image:, video:, audio:,
  # document:, location:, total: }.
  def type_breakdown(message_scope)
    ids = message_scope.pluck(:id)
    return empty_breakdown if ids.empty?

    # group(:file_type) yields the enum's string names ("image"/"video"/…).
    counts = Attachment.where(message_id: ids).group(:file_type).count
    media = MEDIA_FILE_TYPES.transform_values { |name| counts[name].to_i }
    total = ids.size
    with_attachment = counts.values.sum
    media.merge(text: total - with_attachment, total: total)
  end

  def incoming_breakdown
    type_breakdown(incoming_messages)
  end

  def outgoing_breakdown
    type_breakdown(outgoing_messages)
  end

  # Multimedia sent = outgoing messages that carry any attachment.
  def outgoing_media_count
    Attachment.where(message_id: outgoing_messages.select(:id)).distinct.count(:message_id)
  end

  private

  def empty_breakdown
    { text: 0, image: 0, video: 0, audio: 0, document: 0, location: 0, total: 0 }
  end
end
