# Turns an inbound WhatsApp GROUP message webhook into a Chatwoot conversation +
# message, so groups show up in the agent inbox like any other conversation.
#
# Unlike a 1:1 message (one contact ⇄ one conversation), a group has MANY senders
# but ONE conversation. So we:
#   • resolve/create the group locally (by provider_group_id),
#   • keep ONE conversation per group (cached on group.conversation_id),
#   • resolve/create a Contact for the participant who wrote (their phone), link it
#     as a group member, and attach the message to the group conversation with that
#     contact as the sender — so agents see WHO in the group said what.
#
# Idempotent per group (Redis lock) and per message (source_id dedup).
class Jabvox::Whatsapp::IncomingGroupMessageService
  def initialize(channel:, group_id:, value:)
    @channel = channel
    @inbox = channel.inbox
    @account = channel.account
    @provider_group_id = group_id.to_s
    @value = value.to_h.with_indifferent_access
  end

  def perform
    return if @provider_group_id.blank?

    group = resolve_group
    return if group.nil?

    with_group_lock(group.id) do
      Array(@value[:messages]).each do |msg|
        # Resolve the participant contact first: a WhatsApp inbox requires the
        # conversation's contact_inbox source_id to be a real phone, so the group
        # conversation is anchored to the first sender. The room is still identified
        # as a group via additional_attributes + group.conversation_id, and every
        # message keeps its own real sender.
        sender_ci = resolve_sender_contact_inbox(group, msg)
        next if sender_ci.nil?

        conversation = ensure_conversation(group, sender_ci)
        ingest_message(conversation, msg, sender_ci.contact)
      end
    end
  end

  private

  # The group must already exist locally (created via the panel or a prior event).
  # We never auto-create groups from a message — that would bypass the panel/Meta
  # provisioning and the 8-member cap. Unknown groups are ignored (logged upstream).
  def resolve_group
    @account.jabvox_whatsapp_groups.find_by(provider_group_id_jabvox: @provider_group_id)
  end

  # One conversation per group, cached on group.conversation_id. Anchored to the
  # first sender's contact_inbox (a WhatsApp inbox requires a phone-shaped
  # source_id), but flagged as a group room via additional_attributes.
  def ensure_conversation(group, sender_ci)
    existing = group.conversation_id && @account.conversations.find_by(id: group.conversation_id)
    return existing if existing

    conversation = ::Conversation.create!(
      account_id: @account.id, inbox_id: @inbox.id,
      contact_id: sender_ci.contact_id, contact_inbox_id: sender_ci.id,
      additional_attributes: {
        is_whatsapp_group: true,
        whatsapp_group_id: group.id,
        whatsapp_group_provider_id: group.provider_group_id_jabvox,
        group_name: group.name_jabvox
      }
    )
    group.update_columns(conversation_id: conversation.id) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  def ingest_message(conversation, msg, sender_contact)
    source_id = msg[:id].to_s
    return if source_id.present? && conversation.messages.exists?(source_id: source_id)

    body = extract_text(msg)
    return if body.blank? # only text for now; media handled by the base flow later

    conversation.messages.create!(
      account_id: @account.id, inbox_id: @inbox.id,
      message_type: :incoming, status: :sent,
      content: body, source_id: source_id.presence,
      sender: sender_contact,
      content_attributes: {
        whatsapp_group: {
          sender_phone: sender_phone(msg),
          sender_name: sender_display_name(msg)
        }
      }
    )
  end

  # Resolve/create the contact_inbox for the participant who wrote, and record them
  # as a joined member linked to their Chatwoot contact.
  def resolve_sender_contact_inbox(group, msg)
    phone = sender_phone(msg)
    return nil if phone.blank?

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      inbox: @inbox,
      source_id: phone,
      contact_attributes: { phone_number: "+#{phone}", name: sender_display_name(msg) }
    ).perform
    link_member(group, contact_inbox.contact, phone)
    contact_inbox
  end

  # Keep the group_members table in sync: mark the sender as a joined member and
  # link them to their Chatwoot contact (fills the long-empty contact_id).
  def link_member(group, contact, phone)
    member = group.members.find_or_initialize_by(phone_number_jabvox: phone)
    member.account ||= @account
    member.contact_id = contact.id
    member.name_jabvox = contact.name if member.name_jabvox.blank?
    member.invite_status_jabvox = 'joined' if member.invite_status_jabvox.blank? || member.invite_status_jabvox == 'pending'
    member.joined_at_jabvox ||= Time.current
    member.save!(validate: false)
  rescue StandardError => e
    Rails.logger.warn("[Jabvox WhatsApp group member link] #{e.class}: #{e.message}")
  end

  def sender_phone(msg)
    msg[:from].to_s.gsub(/\D/, '')
  end

  def sender_display_name(msg)
    contact = Array(@value[:contacts]).find { |c| c[:wa_id].to_s.gsub(/\D/, '') == sender_phone(msg) }
    contact&.dig(:profile, :name).presence || "+#{sender_phone(msg)}"
  end

  def extract_text(msg)
    msg.dig(:text, :body).presence || msg.dig(:button, :text).presence ||
      msg.dig(:interactive, :list_reply, :title).presence ||
      msg.dig(:interactive, :button_reply, :title).presence
  end

  def with_group_lock(group_id, &)
    acquired = Redis::LockManager.new.with_lock("jabvox_wa_group_msg:#{group_id}", 30.seconds, &)
    yield unless acquired
  rescue StandardError
    yield
  end
end
