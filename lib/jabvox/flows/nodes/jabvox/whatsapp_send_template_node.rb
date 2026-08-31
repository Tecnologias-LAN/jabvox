# frozen_string_literal: true

# jabvox.whatsapp.send_template — envía una plantilla APROBADA de Meta.
#
# EL BUG QUE ESTE NODO NO PUEDE REINTRODUCIR: crear el mensaje devuelve éxito
# aunque Meta lo rechace después, porque el mensaje nace `status: sent` y el
# envío real corre en `SendReplyJob` de forma asíncrona; el error de Meta acaba
# en `content_attributes['external_error']` minutos más tarde. Dentro de Rails
# se corre el job EN EL SITIO (`perform_now`), así que el veredicto de Meta se
# conoce antes de responder: nada de sondeos ni de "unconfirmed".
class Jabvox::Flows::Nodes::Jabvox::WhatsappSendTemplateNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.whatsapp.send_template'
  label 'Enviar plantilla de WhatsApp'

  Structure = Jabvox::Flows::Nodes::WhatsappTemplateStructure
  Payload = Jabvox::Flows::Nodes::WhatsappTemplatePayload

  def perform
    request = read_request
    template = find_template(request)
    structure = template ? Structure.parse(template) : nil
    assert_approved!(structure, request[:template_name])

    resolved = resolve_slots(request)
    assert_slots_filled!(structure, resolved)
    dispatch(request, structure, resolved)
  end

  private

  def read_request
    inbox = find_inbox!(first_filled(param(:inbox), param(:inboxId)), 'la "Bandeja WhatsApp"')
    assert_whatsapp_inbox!(inbox)
    name = first_filled(param(:template), param(:templateName))
    fail_with!('Falta la "Plantilla": elige una plantilla aprobada de esa bandeja.') if name.blank?

    { inbox: inbox, contact: find_contact!(param(:contactId)), template_name: name,
      # `first_filled`, NO `||`: el formulario manda '' cuando el campo se deja
      # en blanco, y en Ruby '' es truthy. Así viajó un idioma vacío a Meta.
      language: first_filled(param(:language)), category: first_filled(param(:category)) }
  end

  # La bandeja DEBE ser de WhatsApp API oficial. Sin esta comprobación, apuntar
  # a otro canal creaba la conversación y publicaba un mensaje normal: el nodo
  # decía "enviado" pero NO salía ninguna plantilla.
  def assert_whatsapp_inbox!(inbox)
    return if inbox.channel_type == 'Channel::Whatsapp'

    available = account.inboxes.where(channel_type: 'Channel::Whatsapp')
                       .map { |i| "#{i.name} (#{i.id})" }
    fail_with!(no_whatsapp_inbox_message) if available.empty?
    fail_with!("La bandeja #{inbox.id} no es una bandeja de WhatsApp API oficial, así que no puede " \
               "enviar plantillas de Meta. Bandejas disponibles: #{available.join(', ')}.")
  end

  def no_whatsapp_inbox_message
    'Esta cuenta de Jabvox no tiene ninguna bandeja de WhatsApp API oficial (WhatsApp Cloud), que es ' \
      'la única que puede enviar plantillas aprobadas de Meta. Conecta una bandeja de WhatsApp Cloud ' \
      'en Jabvox y sincroniza sus plantillas antes de usar este nodo.'
  end

  # Una plantilla puede estar aprobada en VARIOS idiomas: si se pidió uno
  # concreto manda ese; si no, la de la bandeja pedida.
  def find_template(request)
    scope = account.jabvox_whatsapp_templates.where('LOWER(name) = ?', request[:template_name].downcase)
    by_language = request[:language].present? ? scope.where('LOWER(language) = ?', request[:language].downcase) : nil
    by_language&.first || scope.find_by(inbox_id: request[:inbox].id) || scope.first
  end

  # Solo APROBADAS: enviar una en revisión o rechazada la rechaza Meta con un
  # error opaco. Un status ausente no bloquea (forks antiguos).
  def assert_approved!(structure, name)
    status = structure&.dig('status')
    return if status.blank? || status == 'APPROVED'

    fail_with!("La plantilla «#{name}» está en estado #{status}, y solo se pueden enviar plantillas " \
               'APROBADAS por Meta. Elige otra o espera a que Meta la apruebe.')
  end

  # `variableMap` → valores por hueco. `text:<literal>` es un valor fijo;
  # cualquier otro valor es una clave del mapa plano de campos del destinatario.
  def resolve_slots(request)
    fields = field_map(request)
    raw = param(:variableMap) || param(:templateParams)
    return raw.each_with_index.to_h { |v, i| [(i + 1).to_s, resolve_one(v, fields)] } if raw.is_a?(Array)
    return {} unless raw.is_a?(Hash)

    raw.to_h { |k, v| [k.to_s, resolve_one(v, fields)] }
  end

  def resolve_one(source, fields)
    value = source.to_s
    return value.delete_prefix('text:') if value.start_with?('text:')
    return '' if value.empty?

    # Clave del mapa plano. Si no existe la clave, cadena vacía.
    fields[value].to_s
  end

  # Mapa PLANO de campos del destinatario con las claves EXACTAS del fork. Con
  # `leadId` se lee el lead (trae campaña, afiliado y campos propios); si no, el
  # contacto.
  def field_map(request)
    lead_id = param(:leadId).to_s.strip
    return lead_fields(find_lead!(lead_id)) if lead_id.present?

    contact_fields(request[:contact])
  end

  def lead_fields(lead)
    contact = lead.contact
    base = contact_fields(contact).merge(
      'campaign' => lead.jabvox_campaign&.name_jabvox.to_s, 'afiliado' => lead.jabvox_affiliate&.name.to_s,
      'assignee_name' => lead.assignee&.name.to_s, 'assignee_email' => lead.assignee&.email.to_s,
      'lead_number' => lead.lead_number.to_s
    )
    (lead.custom_fields_jabvox || {}).each { |k, v| base["custom:#{k}"] = v.to_s }
    base
  end

  def contact_fields(contact)
    extra = contact&.additional_attributes || {}
    base = { 'nombre' => contact&.name.to_s, 'numero' => contact&.phone_number.to_s,
             'email' => contact&.email.to_s, 'telefono' => contact&.phone_number.to_s,
             'identificador' => contact&.identifier.to_s, 'country' => extra['country'].to_s,
             # Sin lead no hay campaña/afiliado/asignado: quedan vacíos.
             'campaign' => '', 'afiliado' => '', 'assignee_name' => '', 'assignee_email' => '',
             'lead_number' => '' }
    (contact&.custom_attributes || {}).each { |k, v| base["custom:#{k}"] = v.to_s }
    base
  end

  # VALIDACIÓN ANTES DE ENVIAR: si falta algún hueco el error dice cuántos y
  # cuáles, en vez de dejar que Meta devuelva un fallo genérico.
  def assert_slots_filled!(structure, resolved)
    return if structure.nil?

    missing = Structure.missing_slots(structure, resolved)
    fail_with!(Structure.missing_message(structure, missing)) if missing.any?
  end

  def dispatch(request, structure, resolved)
    assert_contact_has_phone!(request[:contact])
    conversation = resolve_conversation(request)
    processed = Payload.body_params(structure, resolved)
    message = create_message(request, structure, conversation, processed, resolved)
    deliver!(message, request[:template_name], conversation)
    build_output(request, structure, message,
                 conversation: conversation, processed: processed, resolved: resolved)
  end

  # El contacto DEBE tener teléfono: sin él Meta rechaza el envío con un error
  # opaco, y ese era el fallo real de producción.
  def assert_contact_has_phone!(contact)
    return if contact.phone_number.present?

    name = contact.name.to_s.strip
    fail_with!("El contacto #{contact.id}#{name.present? ? " («#{name}»)" : ''} NO tiene número de " \
               'teléfono, así que no se le puede enviar un WhatsApp. Añade el teléfono al contacto en ' \
               'Jabvox (en formato internacional, p.ej. +573001112233) o apunta el "ID interno del ' \
               'contacto" a otro contacto.')
  end

  # Reutiliza la conversación más reciente del contacto en ESA bandeja, o crea
  # una: así no se abre un hilo nuevo en cada ejecución del flujo.
  def resolve_conversation(request)
    existing = account.conversations.where(contact_id: request[:contact].id, inbox_id: request[:inbox].id)
                      .order(Arel.sql('CASE WHEN status = 0 THEN 0 ELSE 1 END'), id: :desc).first
    existing || create_conversation(request)
  end

  def create_conversation(request)
    inbox_contact = request[:inbox].contact_inboxes.find_or_create_by!(contact_id: request[:contact].id) do |ci|
      ci.source_id = request[:contact].phone_number.to_s.delete('+')
    end
    account.conversations.create!(inbox_id: request[:inbox].id, contact_id: request[:contact].id,
                                  contact_inbox_id: inbox_contact.id)
  end

  # El mensaje lleva `template_params` en `additional_attributes`: es lo que lee
  # el canal de WhatsApp para mandar la plantilla en vez de un texto suelto.
  def create_message(request, structure, conversation, processed, resolved)
    # `first_filled`, NO `||`: el '' del formulario es truthy en Ruby, y así
    # viajó un idioma vacío que Meta rechazó.
    language = first_filled(request[:language], structure&.dig('language'), 'es')
    category = first_filled(request[:category], structure&.dig('category'), 'UTILITY')
    params = { 'name' => request[:template_name], 'category' => category, 'language' => language,
               'processed_params' => processed }
    components = Payload.components(structure, resolved)
    params['template_components'] = components if components

    conversation.messages.create!(
      account_id: account.id, inbox_id: request[:inbox].id, message_type: :outgoing,
      content: Payload.rendered_content(structure, request[:template_name], processed),
      additional_attributes: { 'template_params' => params }
    )
  end

  # EL ENVÍO, EN EL SITIO. `perform_now` corre el mismo servicio que el job
  # asíncrono, así que al volver el mensaje ya tiene el veredicto real de Meta.
  # Si Meta rechazó, el paso FALLA a propósito: si aquí dijera "éxito", los
  # pasos siguientes darían al cliente por avisado sin haberle llegado nada.
  def deliver!(message, template_name, conversation)
    SendReplyJob.perform_now(message.id)
    message.reload
    return unless message.status.to_s == 'failed'

    detail = message.content_attributes['external_error'].presence || 'sin detalle'
    fail_with!("Meta RECHAZÓ la plantilla «#{template_name}» enviada a la conversación " \
               "#{conversation.display_id}: #{detail}. El mensaje figura en el hilo de Jabvox pero NO " \
               'le llegó al cliente, así que el paso se marca como fallido a propósito.')
  end

  def build_output(request, structure, message, **sent)
    { 'conversationId' => sent[:conversation].display_id, 'messageId' => message.id,
      'templateName' => request[:template_name],
      'language' => message.additional_attributes.dig('template_params', 'language'),
      'category' => message.additional_attributes.dig('template_params', 'category'),
      'processedParams' => sent[:processed], 'content' => message.content,
      'delivery' => message.status.to_s, 'deliveryConfirmed' => %w[delivered read].include?(message.status.to_s),
      # Observabilidad: qué huecos tenía la plantilla y con qué se rellenaron.
      'slots' => structure ? structure['slots'].pluck('key') : [], 'resolvedSlots' => sent[:resolved] }
  end
end
