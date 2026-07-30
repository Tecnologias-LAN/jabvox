class Api::V1::Accounts::Jabvox::WhatsappGroups::GroupsController <
      Api::V1::Accounts::Jabvox::WhatsappGroups::BaseController
  before_action :ensure_admin, except: [:index, :show, :eligibility]
  before_action :set_inbox, only: [:create, :eligibility]
  before_action :set_group, only: [:show, :update, :invite, :add_member, :remove_member, :update_member, :send_message]
  rescue_from Jabvox::Whatsapp::GroupApiError, with: :render_group_api_error

  def index
    groups = Current.account.jabvox_whatsapp_groups.order(created_at: :desc)
    render json: groups.map { |g| serialize(g) }
  end

  def show
    render json: serialize(@group, include_members: true)
  end

  # Reports why groups are (in)eligible for an inbox, so the UI can show the exact
  # reason instead of a generic block. Cheap, read-only, non-admin.
  def eligibility
    channel = @inbox.channel
    render json: {
      eligible: channel.whatsapp_groups_supported?,
      reason: channel.whatsapp_groups_ineligibility_reason,
      feature_enabled: Current.account.feature_enabled?('jabvox_whatsapp_groups')
    }
  end

  def create
    return unless ensure_eligible!(@inbox)

    group = manager(@inbox).create(
      name: group_params[:name], description: group_params[:description],
      created_by: Current.user, member_phones: group_params[:member_phones] || []
    )
    render json: serialize(group, include_members: true), status: :created
  end

  def update
    manager(@group.inbox).update_metadata(@group, name: group_params[:name], description: group_params[:description])
    render json: serialize(@group.reload)
  end

  def invite
    url = manager(@group.inbox).refresh_invite_link(@group)
    render json: { invite_link: url }
  end

  def add_member
    manager(@group.inbox).add_member(@group, member_params[:phone_number], role: member_params[:role] || 'member')
    render json: serialize(@group.reload, include_members: true), status: :created
  end

  def remove_member
    member = @group.members.find(params[:member_id])
    manager(@group.inbox).remove_member(@group, member)
    render json: serialize(@group.reload, include_members: true)
  end

  def update_member
    member = @group.members.find(params[:member_id])
    manager(@group.inbox).update_member_role(@group, member, member_params[:role])
    render json: serialize(@group.reload, include_members: true)
  end

  def send_message
    manager(@group.inbox).send_message(@group, message_params[:text])
    head :ok
  end

  private

  def manager(inbox)
    Jabvox::Whatsapp::GroupManager.new(inbox)
  end

  def set_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id] || group_params[:inbox_id])
  end

  def set_group
    @group = Current.account.jabvox_whatsapp_groups.find(params[:id])
  end

  # Server-side gate mirroring the UI: block group creation on ineligible inboxes.
  # Returns true when eligible; otherwise renders the reason and returns false so
  # the caller can halt.
  def ensure_eligible!(inbox)
    return true if inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.whatsapp_groups_supported?

    reason = inbox.channel.respond_to?(:whatsapp_groups_ineligibility_reason) ? inbox.channel.whatsapp_groups_ineligibility_reason : 'not_cloud_api'
    render json: { error: 'Esta bandeja no es elegible para grupos de WhatsApp', reason: reason }, status: :unprocessable_entity
    false
  end

  def group_params
    params.require(:group).permit(:name, :description, :inbox_id, member_phones: [])
  rescue ActionController::ParameterMissing
    params.permit(:name, :description, :inbox_id, member_phones: [])
  end

  def member_params
    params.require(:member).permit(:phone_number, :role)
  end

  def message_params
    params.require(:message).permit(:text)
  end

  def serialize(group, include_members: false)
    data = {
      id: group.id, name: group.name_jabvox, description: group.description_jabvox,
      status: group.status_jabvox, provider_group_id: group.provider_group_id_jabvox,
      invite_link: group.invite_link_jabvox, inbox_id: group.inbox_id,
      conversation_id: group.conversation_id, active_members_count: group.active_members_count,
      max_members: JabvoxWhatsappGroup::MAX_ACTIVE_MEMBERS, created_at: group.created_at
    }
    data[:members] = group.members.map { |m| serialize_member(m) } if include_members
    data
  end

  def serialize_member(member)
    {
      id: member.id, phone_number: member.phone_number_jabvox, name: member.name_jabvox,
      role: member.role_jabvox, invite_status: member.invite_status_jabvox,
      contact_id: member.contact_id, joined_at: member.joined_at_jabvox
    }
  end

  def render_group_api_error(error)
    render json: { error: error.message }, status: (error.status == 409 ? :conflict : :unprocessable_entity)
  end
end
