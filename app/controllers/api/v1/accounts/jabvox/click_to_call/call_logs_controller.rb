class Api::V1::Accounts::Jabvox::ClickToCall::CallLogsController < Api::V1::Accounts::Jabvox::ClickToCall::BaseController
  before_action :set_call_log, only: [:show, :update]

  def index
    logs = Current.account.jabvox_call_logs.recent.includes(:typification, :contact).limit(100)
    render json: { call_logs: logs.map { |l| serialize(l) } }
  end

  def show
    render json: serialize(@call_log)
  end

  # PATCH /call_logs/:id — typify the call (and persist the recording uniqueid).
  def update
    @call_log.update!(call_log_params.merge(status: 'typified'))
    create_note_if_requested
    render json: serialize(@call_log)
  end

  private

  def set_call_log
    @call_log = Current.account.jabvox_call_logs.find(params[:id])
  end

  # uniqueid is deliberately NOT permitted here: it's set server-side (at originate and on
  # the AMI Hangup event), so a late/empty PATCH from the agent can never blank it out.
  def call_log_params
    params.require(:call_log).permit(:typification_id, :note)
  end

  # Management (gestión) snapshot: state + dynamic answers, mirrored into the note's
  # content_attributes so the timeline renders the same management block used elsewhere.
  def management_attributes
    params.dig(:call_log, :management)
  end

  # When a note OR a management state is provided and the call is tied to a conversation,
  # mirror it as a private note on the conversation so it surfaces in the agent's timeline.
  def create_note_if_requested
    management = management_attributes
    return if @call_log.conversation.blank?
    return if @call_log.note.blank? && management.blank?

    @call_log.conversation.messages.create!(
      account_id: Current.account.id,
      inbox_id: @call_log.conversation.inbox_id,
      message_type: :outgoing,
      private: true,
      content: note_content(management),
      content_attributes: management.present? ? management.to_unsafe_h : {},
      sender: current_user
    )
  rescue StandardError => e
    Rails.logger.error "[ClickToCall] note creation failed: #{e.message}"
  end

  # Falls back to the management state name when the agent left the free-text note empty.
  def note_content(management)
    @call_log.note.presence || management&.dig(:jabvox_management_state_name).presence || '—'
  end

  def serialize(log)
    {
      id: log.id,
      phone_number: log.phone_number,
      status: log.status,
      uniqueid: log.uniqueid,
      note: log.note,
      typification_id: log.typification_id,
      contact_id: log.contact_id,
      conversation_id: log.conversation_id,
      called_at: log.called_at
    }
  end
end
