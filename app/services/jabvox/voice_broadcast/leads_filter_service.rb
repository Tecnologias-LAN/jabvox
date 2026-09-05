# frozen_string_literal: true

# Fuente única de verdad de qué leads apunta una campaña de VOICE BROADCAST.
# Independiente del marcador (dialer): el VB no debe depender de ese módulo. Se usa
# tanto en el formulario (conteo + preview) como al materializar los destinatarios,
# así el número que ve el usuario es exactamente al que se llama.
#
# Acepta un hash plano de filtros:
#   countries: [], management_state_ids: [], affiliate_ids: [], inbox_ids: [],
#   q, email, phone, document, custom: { field_key => value },
#   excluded_lead_ids: [], require_phone: true/false
#
# Las claves de campos personalizados se sanean (slug) antes de tocar el jsonb, así
# la entrada del usuario nunca puede inyectar SQL.
class Jabvox::VoiceBroadcast::LeadsFilterService
  def initialize(account, filters)
    @account = account
    @filters = (filters || {}).with_indifferent_access
  end

  def scope
    leads = @account.jabvox_leads.joins(:contact)
    leads = leads.where("contacts.phone_number IS NOT NULL AND contacts.phone_number <> ''") if @filters[:require_phone]
    leads = apply_countries(leads)
    leads = apply_management_states(leads)
    leads = apply_affiliates(leads)
    leads = apply_inboxes(leads)
    leads = apply_lead_fields(leads)
    leads = apply_custom_fields(leads)
    apply_exclusions(leads)
  end

  private

  def apply_countries(leads)
    countries = Array(@filters[:countries]).compact.reject(&:blank?)
    return leads if countries.empty?

    conds = countries.map { "contacts.additional_attributes->>'country' ILIKE ?" }.join(' OR ')
    leads.where(conds, *countries)
  end

  def apply_affiliates(leads)
    affiliate_ids = Array(@filters[:affiliate_ids]).map(&:to_i).select(&:positive?)
    affiliate_ids.any? ? leads.where(jabvox_affiliate_id: affiliate_ids) : leads
  end

  def apply_inboxes(leads)
    inbox_ids = Array(@filters[:inbox_ids]).map(&:to_i).select(&:positive?)
    return leads if inbox_ids.empty?

    leads.where(contact_id: @account.conversations.where(inbox_id: inbox_ids).select(:contact_id))
  end

  def apply_lead_fields(leads)
    leads = leads.where('contacts.name ILIKE ?', "%#{like(@filters[:q])}%") if @filters[:q].present?
    leads = leads.where('contacts.email ILIKE ?', "%#{like(@filters[:email])}%") if @filters[:email].present?
    leads = leads.where('contacts.phone_number ILIKE ?', "%#{like(@filters[:phone])}%") if @filters[:phone].present?
    apply_document_filter(leads)
  end

  # Documento del lead: mismas fuentes que la lista de leads y el detalle
  # (additional_attributes, campos custom de documento, contact.identifier).
  DOCUMENT_CUSTOM_KEYS = %w[documento documento_c document cedula cedula_c dni nit identificacion identificacion_c].freeze

  def apply_document_filter(leads)
    return leads if @filters[:document].blank?

    doc = "%#{like(@filters[:document])}%"
    custom_conds = DOCUMENT_CUSTOM_KEYS.map { |k| "jabvox_leads.custom_fields_jabvox->>'#{k}' ILIKE :d" }
    sql = "contacts.additional_attributes->>'jabvox_identification_number' ILIKE :d " \
          "OR contacts.identifier ILIKE :d OR #{custom_conds.join(' OR ')}"
    leads.where(sql, d: doc)
  end

  # Escapa comodines de LIKE para que % / _ en la entrada del usuario matcheen literalmente.
  def like(value)
    ActiveRecord::Base.sanitize_sql_like(value.to_s)
  end

  # Delega en el filtro custom compartido (neutral, no del dialer) para que
  # "uno o varios valores" (incl. payloads índice-hash de axios) y la seguridad
  # SQL coincidan con la lista de leads y el envío masivo.
  def apply_custom_fields(leads)
    Jabvox::LeadCustomFilter.apply(leads, @filters[:custom])
  end

  def apply_exclusions(leads)
    excluded = Array(@filters[:excluded_lead_ids]).map(&:to_i).select(&:positive?)
    excluded.any? ? leads.where.not(jabvox_leads: { id: excluded }) : leads
  end

  def apply_management_states(leads) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    state_ids = Array(@filters[:management_state_ids]).map(&:to_s).reject(&:blank?)
    return leads if state_ids.empty?

    include_none = state_ids.include?('none')
    numeric_ids = state_ids.reject { |id| id == 'none' }.map(&:to_i).select(&:positive?)
    state_names = numeric_ids.any? ? @account.jabvox_management_states.where(id: numeric_ids).pluck(:name_jabvox) : []
    return leads if state_names.empty? && !include_none

    msgs_base = @account.messages.where(private: true)
                        .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL")
                        .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''")
    contact_ids_with_any_state = @account.conversations
                                         .where(id: msgs_base.select(:conversation_id))
                                         .select(:contact_id)

    if state_names.any?
      # Por contacto, el mensaje de estado más reciente (mayor ID): matcheamos la
      # ÚLTIMA gestión, no una histórica cualquiera.
      latest_per_contact = msgs_base
                           .joins('INNER JOIN conversations ON conversations.id = messages.conversation_id')
                           .unscope(:order)
                           .group('conversations.contact_id')
                           .select('conversations.contact_id, MAX(messages.id) AS max_id')
      name_conds = state_names.map { "((content_attributes #>> '{}')::json->>'jabvox_management_state_name' = ?)" }.join(' OR ')
      contact_ids_matching = @account.messages
                                     .joins("INNER JOIN (#{latest_per_contact.to_sql}) lpc ON messages.id = lpc.max_id")
                                     .joins('INNER JOIN conversations ON conversations.id = messages.conversation_id')
                                     .where(name_conds, *state_names)
                                     .select('conversations.contact_id')
      if include_none
        leads.where("jabvox_leads.contact_id IN (#{contact_ids_matching.to_sql}) OR " \
                    "jabvox_leads.contact_id NOT IN (#{contact_ids_with_any_state.to_sql})")
      else
        leads.where(contact_id: contact_ids_matching)
      end
    else
      leads.where("jabvox_leads.contact_id NOT IN (#{contact_ids_with_any_state.to_sql})")
    end
  end
end
