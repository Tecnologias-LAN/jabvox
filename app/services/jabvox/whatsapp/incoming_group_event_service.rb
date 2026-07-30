# Applies a WhatsApp Groups API webhook event to local state. Idempotent: it only
# reflects what Meta reports (member joined/left, metadata/status changes) — it
# never sends anything back and never mutates a group outside this channel's
# account. Locks per group id so concurrent events for one group serialize.
class Jabvox::Whatsapp::IncomingGroupEventService
  def initialize(channel:, field:, value:)
    @channel = channel
    @account = channel.account
    @field = field
    @value = value.to_h.with_indifferent_access
  end

  def perform
    group = find_group
    return if group.nil?

    with_group_lock(group.id) do
      case @field
      when 'group_participants_update' then apply_participants(group)
      when 'group_settings_update'     then apply_settings(group)
      when 'group_status_update', 'group_lifecycle_update' then apply_status(group)
      end
    end
  end

  private

  def find_group
    gid = @value[:group_id] || @value.dig(:group, :id) || @value[:id]
    return nil if gid.blank?

    @account.jabvox_whatsapp_groups.find_by(provider_group_id_jabvox: gid)
  end

  def apply_participants(group)
    Array(@value[:participants]).each do |p|
      phone = p[:phone_number].to_s.gsub(/\D/, '')
      next if phone.blank?

      member = group.members.find_or_initialize_by(phone_number_jabvox: phone)
      member.account ||= @account
      apply_participant_action(member, p[:action].to_s)
    end
  end

  def apply_participant_action(member, action)
    case action
    when 'join', 'add'
      member.assign_attributes(invite_status_jabvox: 'joined', joined_at_jabvox: Time.current)
    when 'leave', 'remove'
      member.assign_attributes(invite_status_jabvox: (action == 'leave' ? 'left' : 'removed'), left_at_jabvox: Time.current)
    when 'promote'
      member.role_jabvox = 'admin'
    when 'demote'
      member.role_jabvox = 'member'
    end
    member.save!(validate: false)
  end

  def apply_settings(group)
    attrs = {}
    attrs[:name_jabvox] = @value[:subject] if @value.key?(:subject)
    attrs[:description_jabvox] = @value[:description] if @value.key?(:description)
    group.update!(attrs) if attrs.any?
  end

  def apply_status(group)
    status = @value[:status].to_s
    return unless %w[active archived].include?(status)

    group.update!(status_jabvox: status)
  end

  # Serialize concurrent events for the same group. with_lock returns false
  # (without yielding) if the lock can't be acquired, and may raise if Redis is
  # unavailable — in both cases fall back to running the (idempotent) update
  # directly rather than dropping the event.
  def with_group_lock(group_id, &)
    acquired = Redis::LockManager.new.with_lock("jabvox_wa_group_evt:#{group_id}", 30.seconds, &)
    yield unless acquired
  rescue StandardError
    yield
  end
end
