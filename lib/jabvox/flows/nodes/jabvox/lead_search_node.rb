# frozen_string_literal: true

# jabvox.lead.search — nodo UNIFICADO de búsqueda de leads. Los 6 modos
# normalizan la salida a `{ mode, count, leads: [...] }`, de modo que un bucle
# sobre `{{node.<id>.items}}` funciona igual venga de donde venga.
class Jabvox::Flows::Nodes::Jabvox::LeadSearchNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.contact.search'
  # Tipo anterior: los flujos guardados lo siguen usando.
  aliases 'jabvox.lead.search'
  label 'Buscar Contactos'
  items_path 'leads'

  # Tope de seguridad. `limit` es OPCIONAL: dejarlo vacío aplica este tope, NUNCA
  # "sin límite" (una cuenta con decenas de miles de leads tumbaría el nodo).
  SAFETY_LIMIT = 500
  FIELD_OPERATORS = %w[contains equals empty not_empty].freeze

  def perform
    case first_filled(param(:mode), 'by_field')
    when 'by_id' then by_id
    when 'by_label' then by_label
    when 'by_date' then by_date
    when 'list' then by_list
    when 'advanced' then advanced
    else by_field
    end
  end

  private

  def limit
    @limit ||= int_or(param(:limit), SAFETY_LIMIT, min: 1, max: SAFETY_LIMIT)
  end

  # Los "leads" son hoy CONTACTOS: la tabla jabvox_leads ya no existe y campaña, afiliado,
  # responsable y campos personalizados viven en el propio contacto.
  def base_scope
    account.contacts.includes(:jabvox_campaign, :jabvox_affiliate, :assignee)
  end

  def result(mode, leads, extra = {})
    { 'mode' => mode, 'count' => leads.length,
      'leads' => leads.map { |l| slim(l) } }.merge(extra)
  end

  # Forma COMPACTA y común a los 6 modos, para que sean intercambiables al
  # iterar con el bucle.
  # Se conservan las claves de salida ('id', 'contact_id', 'lead_number'…) aunque ya no haya
  # lead: las automatizaciones ya construidas las referencian y cambiarlas las rompería.
  # Ahora `id` y `contact_id` son el mismo valor, y `lead_number` viaja vacío.
  def slim(lead)
    contact = lead
    { 'id' => lead.id, 'lead_number' => nil,
      'contact' => contact_view(contact),
      'contact_id' => lead.id,
      # Se publica en la fila para poder ramificar dentro del bucle sin filtrar.
      'has_phone' => contact&.phone_number.present?,
      'campaign' => lead.jabvox_campaign&.name_jabvox,
      'assignee_name' => lead.assignee&.name,
      'custom_fields_jabvox' => lead.custom_fields_jabvox || {} }
  end

  # El usuario elige si da el NÚMERO visible (#5) o la PK interna. Sin `idKind`
  # ni `leadNumber` se trata `leadId` como PK, que es lo que hacían los flujos
  # guardados antes de existir la opción.
  def by_id
    kind = first_filled(param(:idKind), param(:leadNumber).present? ? 'lead_number' : 'internal')
    lead = kind == 'lead_number' ? by_lead_number : base_scope.find_by(id: param(:leadId).to_s.strip)
    fail_with!(missing_lead_message) if lead.nil?

    result('by_id', [lead], 'lead' => slim(lead))
  end

  # El número de lead desapareció con la tabla. Los flujos guardados que lo usaban siguen
  # funcionando tratándolo como id de contacto, que es el único identificador que queda.
  def by_lead_number
    number = first_filled(param(:leadNumber), param(:leadId))
    base_scope.find_by(id: number.to_i) if number.present?
  end

  def missing_lead_message
    'No se encontró el lead: revisa el número de lead (#N visible en Jabvox) o su ID interno. ' \
      'Si viene de un paso anterior, comprueba que ese paso lo sigue devolviendo.'
  end

  # Por ETIQUETA del contacto: es el set que marca a un lead para no volver a
  # procesarlo en la siguiente vuelta.
  def by_label
    label = param(:label).to_s.strip.downcase
    fail_with!('La búsqueda por etiqueta requiere elegir la etiqueta.') if label.blank?

    contact_ids = account.contacts.tagged_with(label).limit(SAFETY_LIMIT).pluck(:id)
    leads = contact_ids.any? ? base_scope.where(contact_id: contact_ids).limit(limit).to_a : []
    result('by_label', leads, 'label' => label, 'contactsMatched' => contact_ids.length)
  end

  # Por CAMPO personalizado del lead (`custom_fields_jabvox`).
  def by_field
    field = param(:field).to_s.strip
    fail_with!('La búsqueda por campo requiere elegir el campo.') if field.blank?

    operator = FIELD_OPERATORS.include?(param(:operator).to_s) ? param(:operator).to_s : 'contains'
    value = param(:value).to_s.strip
    fail_with!(value_required_message) if %w[contains equals].include?(operator) && value.blank?

    leads = field_scope(field, operator, value).limit(limit).to_a
    result('by_field', leads, 'field' => field, 'operator' => operator, 'value' => value)
  end

  def value_required_message
    'La búsqueda por campo requiere un valor con los operadores "contiene" e "igual a".'
  end

  def field_scope(field, operator, value)
    column = Arel.sql("contacts.custom_fields_jabvox->>#{ActiveRecord::Base.connection.quote(field)}")
    case operator
    when 'equals' then base_scope.where("#{column} = ?", value)
    when 'empty' then base_scope.where("#{column} IS NULL OR #{column} = ''")
    when 'not_empty' then base_scope.where("#{column} IS NOT NULL AND #{column} <> ''")
    else base_scope.where("#{column} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(value)}%")
    end
  end

  # Por FECHA: compara solo mes y día (cumpleaños) o la fecha completa.
  def by_date
    field = first_filled(param(:dateField), param(:field))
    fail_with!('La búsqueda por fecha requiere el campo de fecha a comparar.') if field.blank?

    target = Date.current + int_or(param(:offsetDays), 0).days
    full_date = param(:compareMode).to_s == 'full_date'
    leads = date_matches(field, target, full_date)
    result('by_date', leads, 'field' => field, 'targetDate' => target.iso8601,
                             'compareMode' => full_date ? 'full_date' : 'month_day')
  end

  # El campo es texto libre en JSON, así que la comparación se hace en Ruby:
  # empujarla a SQL exigiría que TODAS las filas tuvieran una fecha parseable.
  def date_matches(field, target, full_date)
    base_scope.where.not('contacts.custom_fields_jabvox->>? IS NULL', field)
              .limit(SAFETY_LIMIT).select do |lead|
      stored = parse_date(lead.custom_fields_jabvox.to_h[field])
      next false if stored.nil?

      full_date ? stored == target : (stored.month == target.month && stored.day == target.day)
    end.first(limit)
  end

  def parse_date(raw)
    Date.parse(raw.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def by_list
    leads = base_scope.ordered.limit(limit).to_a
    result('list', leads)
  end

  # Condiciones múltiples sobre los campos personalizados.
  def advanced
    group = parse_conditions(param(:conditions))
    leads = base_scope.limit(SAFETY_LIMIT).select { |lead| group_matches?(lead, group) }.first(limit)
    result('advanced', leads, 'match' => group['match'], 'rules' => group['rules'].length)
  end

  def group_matches?(lead, group)
    fields = (lead.custom_fields_jabvox || {})
    checks = group['rules'].map { |rule| rule_matches?(fields, rule) }
    group['match'] == 'any' ? checks.any? : checks.all?
  end

  def rule_matches?(fields, rule)
    Jabvox::Flows::Engine::Condition.evaluate(fields[rule['field']], rule['operator'], rule['value'])
  end

  # Se descartan las filas que el usuario añadió y dejó sin campo: son ruido del
  # editor, no una condición que deba fallar la ejecución.
  def parse_conditions(raw)
    source = raw.is_a?(String) ? parse_json(raw) : raw
    fail_with!(no_conditions_message) unless source.is_a?(Hash)

    group = source.deep_stringify_keys
    rules = Array(group['rules']).filter_map { |r| normalize_rule(r) }
    fail_with!(no_conditions_message) if rules.empty?

    { 'match' => group['match'].to_s == 'any' ? 'any' : 'all', 'rules' => rules }
  end

  def normalize_rule(raw)
    return nil unless raw.is_a?(Hash)

    rule = raw.deep_stringify_keys
    field = rule['field'].to_s.strip
    operator = rule['operator'].to_s.strip
    return nil if field.blank? && operator.blank?

    fail_with!('Hay una condición sin campo: elige un campo en cada fila o quítala.') if field.blank?
    fail_with!("La condición sobre \"#{field}\" no tiene operador.") if operator.blank?

    { 'field' => field, 'operator' => operator, 'value' => rule['value'] }
  end

  def parse_json(text)
    JSON.parse(text.strip)
  rescue JSON::ParserError
    fail_with!("Las condiciones no son válidas: se esperaba una lista y llegó el texto \"#{text.strip[0, 60]}\".")
  end

  def no_conditions_message
    'Añade al menos una condición para buscar leads por condiciones múltiples.'
  end
end
