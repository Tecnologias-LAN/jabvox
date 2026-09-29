class Api::V1::Accounts::Jabvox::ClickToCall::CallsController < Api::V1::Accounts::Jabvox::ClickToCall::BaseController
  # POST /calls — start a click-to-call. Resolves the number server-side from the
  # contact/lead, creates the call log, then sends the AMI Originate.
  def create
    config = Current.account.jabvox_voip_config
    return render_error('No hay configuración VoIP') unless config&.host.present?

    extension = agent_extension
    if extension.blank?
      return render_error(
        'Tu usuario no tiene extensión asignada en esta cuenta. La extensión debe ser la de quien llama (Ajustes → VoIP → extensiones por usuario).'
      )
    end

    phone, contact, conversation = resolve_target
    return render_error('No se encontró un número para llamar') if phone.blank?

    call_log = Current.account.jabvox_call_logs.create!(
      user: current_user, contact: contact, conversation: conversation,
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

  # Devuelve [phone, contact, conversation]. El número a marcar sale del dial_field de la
  # configuración VoIP (por defecto, el teléfono del contacto); un campo personalizado se lee
  # del propio contacto y se normaliza con el prefijo configurado.
  #
  # `lead_id` se sigue aceptando como alias de `contact_id` para las llamadas que aún lo
  # envíen: tras retirar Leads, ambos identifican al mismo contacto.
  def resolve_target
    config = Current.account.jabvox_voip_config
    contact_id = params[:contact_id].presence || params[:lead_id].presence
    contact = Current.account.contacts.find_by(id: contact_id) if contact_id
    conversation = Current.account.conversations.find_by(display_id: params[:conversation_id]) if params[:conversation_id].present?
    contact ||= conversation&.contact
    [dial_number(contact, config), contact, conversation]
  end

  def dial_number(contact, config)
    return nil unless contact

    Jabvox::DialNumberResolver.resolve(
      lead: contact, field: config&.dial_field_jabvox, prefix: config&.dial_prefix_jabvox
    )
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
