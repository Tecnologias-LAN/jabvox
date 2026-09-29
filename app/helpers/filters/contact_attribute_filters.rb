module Filters::ContactAttributeFilters
  # Filtros de conversación por datos del CONTACTO (nombre, teléfono, correo, documento).
  #
  # Viven en otra tabla, así que se resuelven con un subquery en vez de un JOIN: el filtro se
  # compone concatenando condiciones sobre `base_relation`, y un join afectaría al resto de
  # condiciones y podría duplicar filas.
  #
  # El nombre de la columna NUNCA viene del cliente: sale del YAML de configuración y además
  # se valida contra una lista blanca, así que no es vía de inyección.
  CONTACT_FILTER_COLUMNS = %w[name phone_number email identifier jabvox_identification_number].freeze

  # Filtra conversaciones por una COLUMNA del contacto (nombre, teléfono, email).
  #
  # Se resuelve con un subquery en vez de un JOIN porque el filtro se compone por
  # concatenación de condiciones sobre `base_relation`: añadir un join aquí afectaría al
  # resto de condiciones y podría duplicar filas. El nombre de la columna NO viene del
  # cliente, sale del YAML de configuración, así que no es vía de inyección.
  def handle_contact_attribute(current_filter, query_hash, filter_operator_value)
    column = contact_column_for(current_filter)
    target = current_filter['data_type'] == 'text_case_insensitive' ? "LOWER(contacts.#{column})" : "contacts.#{column}"
    contact_subquery(target, filter_operator_value, query_hash)
  end

  # Igual que el anterior, pero la clave vive dentro de additional_attributes del contacto
  # (el documento de identidad de Jabvox).
  def handle_contact_jsonb_attribute(current_filter, query_hash, filter_operator_value)
    key = contact_column_for(current_filter)
    contact_subquery("LOWER(contacts.additional_attributes ->> '#{key}')", filter_operator_value, query_hash)
  end

  # Subquery en vez de JOIN: el filtro se compone concatenando condiciones sobre
  # `base_relation`, así que un join afectaría al resto y podría duplicar filas.
  # Conversations::FilterService baja el valor a minúsculas para que esto case.
  def contact_subquery(target, filter_operator_value, query_hash)
    "#{filter_config[:table_name]}.contact_id IN " \
      "(SELECT contacts.id FROM contacts WHERE contacts.account_id = #{filter_config[:table_name]}.account_id " \
      "AND #{target} #{filter_operator_value}) #{query_hash[:query_operator]}"
  end

  def contact_column_for(current_filter)
    column = current_filter['contact_column'].to_s
    raise CustomExceptions::CustomFilter::InvalidAttribute.new(key: column, allowed_keys: CONTACT_FILTER_COLUMNS) \
      unless CONTACT_FILTER_COLUMNS.include?(column)

    column
  end
end
