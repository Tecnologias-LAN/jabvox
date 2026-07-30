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

  def update_member_role(group, member, role)
    @provider.update_participant_role(group.provider_group_id_jabvox, member.phone_number_jabvox, role) if group.provisioned?
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

  def refresh_invite_link(group)
    return unless group.provisioned?

    link = @provider.invite_link(group.provider_group_id_jabvox)
    url = link['invite_link'] || link.dig('invite', 'link')
    group.update!(invite_link_jabvox: url) if url.present?
    url
  end

  def send_message(group, text)
    raise Jabvox::Whatsapp::GroupApiError.new('Group is not provisioned yet', 409) unless group.provisioned?

    @provider.send_text(group.provider_group_id_jabvox, text)
  end

  private

  def normalize(phone)
    phone.to_s.gsub(/\D/, '')
  end
end
