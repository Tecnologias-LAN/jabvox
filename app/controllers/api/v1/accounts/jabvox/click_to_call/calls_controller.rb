class Api::V1::Accounts::Jabvox::ClickToCall::CallsController < Api::V1::Accounts::Jabvox::ClickToCall::BaseController
  # POST /calls — start a click-to-call. Resolves the number server-side from the
  # contact/lead, creates the call log, then sends the AMI Originate.
  def create
    config = Current.account.jabvox_voip_config
    return render_error('No hay configuración VoIP') unless config&.host.present?

    extension = agent_extension
    return render_error('No tienes una extensión asignada') if extension.blank?

    phone, contact, lead, conversation = resolve_target
    return render_error('No se encontró un número para llamar') if phone.blank?

    call_log = Current.account.jabvox_call_logs.create!(
      user: current_user, contact: contact, jabvox_lead: lead, conversation: conversation,
      phone_number: phone, extension: extension, status: 'calling', called_at: Time.current
    )

    result = Jabvox::VoipService.new(config).originate_click_to_call(
      extension: extension, phone: phone, call_log_id: call_log.id, user_id: current_user.id
    )

    unless result[:success]
      call_log.update!(status: 'failed')
      return render_error(result[:message] || 'No se pudo iniciar la llamada')
    end

    # Capture the Asterisk uniqueid early (independent of the Hangup event) so the call
    # is always linkable to its CDR row + typification.
    Jabvox::CaptureClickToCallUniqueidJob.perform_later(call_log.id)

    render json: { call_log_id: call_log.id, message: 'Llamada iniciada' }
  end

  # DELETE /calls/:id — hang up the agent's active leg.
  def destroy
    call_log = Current.account.jabvox_call_logs.find(params[:id])
    config = Current.account.jabvox_voip_config
    # Channel-specific hangup (by CTCALL_ID + account), never by bare extension, so a
    # colliding extension on another account sharing the PBX is never affected.
    Jabvox::VoipService.new(config).hangup(call_log_id: call_log.id, account_id: Current.account.id) if config&.host.present?
    call_log.update!(status: 'ended') if call_log.status == 'calling'
    head :no_content
  end

  private

  def agent_extension
    Current.account.jabvox_user_extensions.find_by(user_id: current_user.id)&.extension_jabvox
  end

  # Returns [phone, contact, lead, conversation] resolved from the params.
  def resolve_target
    if params[:lead_id].present?
      lead = Current.account.jabvox_leads.find_by(id: params[:lead_id])
      return [lead&.contact&.phone_number, lead&.contact, lead, nil]
    end

    contact = Current.account.contacts.find_by(id: params[:contact_id]) if params[:contact_id].present?
    conversation = Current.account.conversations.find_by(display_id: params[:conversation_id]) if params[:conversation_id].present?
    contact ||= conversation&.contact
    [contact&.phone_number, contact, nil, conversation]
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
