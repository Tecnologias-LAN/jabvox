# Orchestrates a WhatsApp group's lifecycle across the local DB and Meta's Groups
# API for one inbox. Keeps the controller thin and the persistence + remote calls
# in one place. Every write validates the 8-member cap through the model, so no
# path can exceed it. Raises Jabvox::Whatsapp::GroupApiError on a Meta failure.
class Jabvox::Whatsapp::GroupManager
  def initialize(inbox)
    @inbox = inbox
    @channel = inbox.channel
    @account = inbox.account
    @provider = Jabvox::Whatsapp::GroupProviderService.new(@channel)
  end

  # Create the group on Meta first, then persist locally with the provider id so
  # the two never diverge; a Meta failure raises before we write anything.
  def create(name:, description:, created_by:, member_phones: [])
    remote = @provider.create_group(name, description: description)
    group = JabvoxWhatsappGroup.create!(
      account: @account, inbox: @inbox, created_by: created_by,
      name_jabvox: name, description_jabvox: description,
      provider_group_id_jabvox: remote['id'] || remote.dig('groups', 0, 'id'),
      status_jabvox: 'active'
    )
    Array(member_phones).first(JabvoxWhatsappGroup::MAX_ACTIVE_MEMBERS).each do |phone|
      add_member(group, phone)
    end
    refresh_invite_link(group)
    group
  end

  # "Adding" a member = record it as pending and (once the group is provisioned)
  # let them join via the invite link. Meta groups are invite-only; we never force
  # someone in. The model validation enforces the 8-member ceiling.
  def add_member(group, phone, role: 'member')
    group.members.create!(
      account: @account, phone_number_jabvox: normalize(phone),
      role_jabvox: role, invite_status_jabvox: 'pending'
    )
  end

  def remove_member(group, member)
    @provider.remove_participant(group.provider_group_id_jabvox, member.phone_number_jabvox) if group.provisioned?
    member.update!(invite_status_jabvox: 'removed', left_at_jabvox: Time.current)
  end

  # Meta's Groups API has NO endpoint to set a participant's role; roles change only
  # via the WhatsApp app and reach us through the group_participants_update webhook
  # (promote/demote). So this updates ONLY local state — it never calls Meta.
  def update_member_role(_group, member, role)
    member.update!(role_jabvox: role)
  end

  def update_metadata(group, attrs)
    if group.provisioned?
      @provider.update_metadata(group.provider_group_id_jabvox,
                                { subject: attrs[:name], description: attrs[:description] })
    end
    group.update!(name_jabvox: attrs[:name].presence || group.name_jabvox,
                  description_jabvox: attrs.key?(:description) ? attrs[:description] : group.description_jabvox)
  end

  # Fetch the current invite link from Meta and cache it locally.
  def refresh_invite_link(group)
    return unless group.provisioned?

    link = @provider.invite_link(group.provider_group_id_jabvox)
    persist_invite_url(group, link)
  end

  # Rotate the invite link (invalidates the old one), then cache the new URL.
  def reset_invite_link(group)
    return unless group.provisioned?

    link = @provider.reset_invite_link(group.provider_group_id_jabvox)
    persist_invite_url(group, link)
  end

  # Send a text to the group via Meta AND persist it as an outgoing message in the
  # group's conversation, so the send shows up in the agent inbox (and counts in
  # reports) like any other outbound message. `sent_by` is the agent (optional).
  def send_message(group, text, sent_by: nil)
    raise Jabvox::Whatsapp::GroupApiError.new('Group is not provisioned yet', 409) unless group.provisioned?

    response = @provider.send_text(group.provider_group_id_jabvox, text)
    persist_outgoing_message(group, text, response, sent_by)
    response
  end

  private

  # Store the outbound group message locally so it appears in the conversation and
  # counts in reports. Best-effort: a persistence failure must not fail the send
  # (Meta already accepted it), so errors are logged, not raised.
  def persist_outgoing_message(group, text, response, sent_by)
    conversation = group_conversation(group)
    return if conversation.nil?

    wamid = response.is_a?(Hash) ? response.dig('messages', 0, 'id') : nil
    conversation.messages.create!(
      account_id: @account.id, inbox_id: group.inbox_id,
      message_type: :outgoing, status: :sent,
      content: text, source_id: wamid,
      sender: sent_by,
      content_attributes: { whatsapp_group: { outbound: true } }
    )
  rescue StandardError => e
    Rails.logger.warn("[Jabvox WhatsApp group send persist] #{e.class}: #{e.message}")
  end

  # The group's conversation (created on the first inbound message). If the group
  # hasn't received anything yet there is no conversation; the send still goes out,
  # it just won't have a local thread until the first inbound arrives.
  def group_conversation(group)
    group.conversation_id && @account.conversations.find_by(id: group.conversation_id)
  end

  # Meta returns the URL under `invite_link` (some SDKs nest it under invite.link);
  # accept both, cache it on the group, and return it.
  def persist_invite_url(group, link)
    url = link['invite_link'] || link.dig('invite', 'link')
    group.update!(invite_link_jabvox: url) if url.present?
    url
  end

  def normalize(phone)
    phone.to_s.gsub(/\D/, '')
  end
end
