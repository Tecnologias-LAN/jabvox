# Records label add/remove intervals for a conversation into
# jabvox_conversation_label_logs, so the WhatsApp report can measure how long each
# label stayed applied. Hooks the same label_list diff Chatwoot already computes,
# but unlike create_label_change it does NOT require a Current.user, so
# automation-driven label changes are captured too.
module Jabvox::ConversationLabelLogging
  extend ActiveSupport::Concern

  included do
    after_update :jabvox_log_label_changes, if: :saved_change_to_label_list?
  end

  private

  def jabvox_log_label_changes
    previous_labels, current_labels = saved_change_to_label_list
    return unless previous_labels.is_a?(Array) && current_labels.is_a?(Array)

    now = Time.current
    (current_labels - previous_labels).each { |label| jabvox_open_label_log(label, now) }
    (previous_labels - current_labels).each { |label| jabvox_close_label_log(label, now) }
  rescue StandardError => e
    Rails.logger.error("[Jabvox label log] conversation=#{id} #{e.class}: #{e.message}")
  end

  # Open an interval unless one is already open (idempotent on the unique index).
  def jabvox_open_label_log(label, at)
    return if JabvoxConversationLabelLog.open.exists?(conversation_id: id, label_jabvox: label)

    JabvoxConversationLabelLog.create!(
      account_id: account_id, conversation_id: id,
      label_jabvox: label, applied_at_jabvox: at
    )
  end

  def jabvox_close_label_log(label, at)
    # At most one open interval per (conversation, label) — the unique index
    # guarantees it — so closing the single open row is enough.
    log = JabvoxConversationLabelLog.open.find_by(conversation_id: id, label_jabvox: label)
    log&.update!(removed_at_jabvox: at)
  end
end
