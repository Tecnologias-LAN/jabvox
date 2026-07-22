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
    # Un payload malformado (call_log como string/array) no debe tumbar el update.
    return render json: { error: 'invalid payload' }, status: :bad_request unless params[:call_log].is_a?(ActionController::Parameters)

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
  # The typification must belong to THIS account (a foreign id is dropped).
  def call_log_params
    permitted = params.require(:call_log).permit(:typification_id, :note)
    if permitted[:typification_id].present? &&
       !Current.account.jabvox_typifications.exists?(id: permitted[:typification_id])
      permitted[:typification_id] = nil
    end
    permitted
  end

  # Management (gestión) snapshot: state + dynamic answers, mirrored into the note's
  # content_attributes so the timeline renders the same management block used elsewhere.
  def management_attributes
    params.dig(:call_log, :management)
  end

  # When a note, a management state OR a typification is provided, mirror it as a
  # private note on the contact's conversation so it surfaces in the agent's
  # timeline and the lead detail's Notes tab. Si el call log no tiene conversación
  # vinculada (click-to-call sobre un contacto sin conversación previa), se crea/
  # encuentra una — antes se hacía `return` y la gestión se perdía de la vista.
  def create_note_if_requested
    management = management_attributes
    return if @call_log.note.blank? && management.blank? && @call_log.typification_id.blank?

    conversation = @call_log.conversation || find_or_create_conversation_for_log
    return if conversation.blank?

    conversation.messages.create!(
      account_id: Current.account.id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      private: true,
      content: note_content(management),
      content_attributes: note_content_attributes(management),
      sender: current_user
    )
  rescue StandardError => e
    Rails.logger.error "[ClickToCall] note creation failed: #{e.message}"
  end

  def note_content_attributes(management)
    attrs = (management.present? ? management.to_unsafe_h : {})
            .merge('jabvox_call_source' => 'click_to_call')
    attrs['jabvox_typification_name'] = typification_name if typification_name.present?
    attrs
  end

  # Conversación del contacto para colgar la gestión cuando el call log no tiene
  # una vinculada. Reutiliza la más reciente del contacto; si no existe, crea una
  # (misma lógica que el listener AMI). La deja además vinculada al call log.
  def find_or_create_conversation_for_log
    contact = @call_log.contact
    return nil if contact.blank?

    conv = Current.account.conversations.where(contact_id: contact.id).order(id: :desc).first
    conv ||= build_conversation_for_contact(contact)
    return nil if conv.blank?

    @call_log.update_columns(conversation_id: conv.id) if @call_log.conversation_id.blank? # rubocop:disable Rails/SkipsModelValidations
    conv
  end

  def build_conversation_for_contact(contact)
    inbox = Current.account.inboxes.first
    return nil if inbox.blank?

    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) do |ci|
      ci.source_id = SecureRandom.uuid
    end
    Conversation.create!(
      account_id: Current.account.id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    )
  rescue StandardError => e
    Rails.logger.error "[ClickToCall] conversation creation failed: #{e.message}"
    nil
  end

  def typification_name
    @typification_name ||= @call_log.typification_id &&
                           Current.account.jabvox_typifications.find_by(id: @call_log.typification_id)&.name.to_s
  end

  # Falls back through: free-text note → management state → typification name.
  def note_content(management)
    @call_log.note.presence ||
      management&.dig(:jabvox_management_state_name).presence ||
      typification_name.presence || '—'
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
