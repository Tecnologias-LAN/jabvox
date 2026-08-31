# frozen_string_literal: true

# jabvox.lead.update_details — edición unificada del lead: contacto
# (tel/email/país/documento), campaña, agente asignado y campos personalizados,
# todo en una transacción. Solo se tocan los campos que llegan informados.
class Jabvox::Flows::Nodes::Jabvox::LeadUpdateDetailsNode < Jabvox::Flows::Nodes::Jabvox::LeadSearchNode
  type 'jabvox.lead.update_details'
  label 'Actualizar Lead'

  # country y documento no son columnas del contacto: viven en su JSON.
  ADDITIONAL_KEYS = { 'country' => 'country',
                      'identification' => 'jabvox_identification_number' }.freeze

  def perform
    lead = find_lead_for_update!
    ActiveRecord::Base.transaction do
      update_contact_fields(lead)
      update_assignee(lead)
      update_campaign(lead)
      update_custom_fields(lead)
    end
    # El endpoint original solo devolvía { id }: aquí se relee el lead para
    # que los pasos siguientes encadenen sobre su estado REAL.
    slim(base_scope.find(lead.id)).merge('updated' => true)
  rescue ActiveRecord::RecordInvalid => e
    fail_with!("No se pudo actualizar el lead: #{e.record.errors.full_messages.join(', ')}.")
  end

  private

  def find_lead_for_update!
    lead_id = require_id!(param(:leadId), 'el ID interno del lead')
    lead = account.jabvox_leads.includes(:contact).find_by(id: lead_id)
    return lead if lead

    fail_with!("El lead #{lead_id} no existe en esta cuenta. Comprueba que sea el ID INTERNO " \
               '(campo `id` de la salida del nodo de búsqueda), no el número #N visible en Jabvox.')
  end

  def update_contact_fields(lead)
    contact = lead.contact
    return if contact.blank?

    attrs = {}
    attrs[:phone_number] = param(:phone_number).to_s.strip unless blank_param?(param(:phone_number))
    attrs[:email] = param(:email).to_s.strip unless blank_param?(param(:email))
    additional = merged_additional(contact)
    attrs[:additional_attributes] = additional if additional
    contact.update!(attrs) if attrs.present?
  end

  # Fusión sobre additional_attributes: escribir el hash entero borraría el resto.
  def merged_additional(contact)
    changes = ADDITIONAL_KEYS.filter_map do |param_key, attr_key|
      [attr_key, param(param_key).to_s.strip] unless blank_param?(param(param_key))
    end
    return nil if changes.empty?

    (contact.additional_attributes || {}).merge(changes.to_h)
  end

  def update_assignee(lead)
    return if blank_param?(param(:assigneeId))

    assignee = account.users.find_by(id: param(:assigneeId).to_s.strip)
    fail_with!("El agente #{param(:assigneeId)} no pertenece a esta cuenta.") if assignee.nil?

    lead.update!(assignee: assignee)
    Jabvox::LeadConversationAssignmentSync.new(account).sync_lead(lead, assignee)
  end

  def update_campaign(lead)
    return if blank_param?(param(:campaign_name))

    lead.update!(jabvox_campaign: find_or_create_campaign(param(:campaign_name).to_s.strip))
  end

  def find_or_create_campaign(name)
    JabvoxCampaign.find_or_create_by!(account: account, name_jabvox: name)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def update_custom_fields(lead)
    incoming = clean_field_map(param(:custom_fields))
    return if incoming.blank?

    result = Jabvox::LeadCustomFieldsSanitizer.new(account, lead.custom_fields_jabvox, incoming).call
    fail_with!("Campos personalizados no válidos: #{result.errors.join(', ')}.") unless result.valid?

    lead.update!(custom_fields_jabvox: result.data)
  end

  # El editor de pares campo → valor; los flujos antiguos lo guardaban en JSON.
  def clean_field_map(raw)
    source = raw.is_a?(String) ? parse_field_map(raw) : raw
    return {} unless source.is_a?(Hash)

    source.transform_keys { |k| k.to_s.strip }.except('')
  end

  def parse_field_map(text)
    trimmed = text.strip
    return {} if trimmed.blank?

    JSON.parse(trimmed)
  rescue JSON::ParserError
    fail_with!('Los campos personalizados no son válidos: se esperaba una lista de campo → valor ' \
               "y llegó el texto \"#{trimmed[0, 60]}\".")
  end
end
