# frozen_string_literal: true

# jabvox.contact.find — busca contactos por un CRITERIO seleccionable (nombre,
# email, teléfono, identificador, país, ciudad, empresa, etiqueta o un atributo
# personalizado) con un operador por tipo. Devuelve `{ count, contacts }` para
# encadenar un bucle sobre la colección.
#
# Compatibilidad: los flujos guardados que mandaban `q` (texto único) siguen
# funcionando con el OR fijo de antes cuando no se elige `field`.
class Jabvox::Flows::Nodes::Jabvox::ContactFindNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.contact.find'
  label 'Buscar contactos'
  items_path 'contacts'

  DEFAULT_LIMIT = 50
  MAX_LIMIT = 500

  def perform
    limit = int_or(param(:limit), DEFAULT_LIMIT, min: 1, max: MAX_LIMIT)
    rows = scope.order(id: :desc).limit(limit).to_a
    { 'field' => criterion, 'operator' => operator, 'value' => value, 'q' => legacy_q,
      'count' => rows.length, 'limit' => limit, 'truncated' => rows.length >= limit,
      'contacts' => rows.map { |c| contact_view(c).merge('contactId' => c.id) } }
  end

  private

  # Base precargando empresa para que `contact_view` no dispare una consulta por fila.
  def base_scope
    account.contacts.includes(:company)
  end

  def criterion
    first_filled(param(:field))
  end

  def operator
    first_filled(param(:operator), 'contains')
  end

  def value
    param(:value).to_s.strip
  end

  def legacy_q
    first_filled(param(:q))
  end

  # Sin criterio elegido se cae al comportamiento histórico (OR sobre `q`).
  def scope
    return legacy_scope if criterion.blank?

    field = criterion
    return company_scope if field == 'company'
    return label_scope if field == 'label'
    return custom_attr_scope(field.delete_prefix('custom:')) if field.start_with?('custom:')

    column_scope(field)
  end

  # --- Criterios ---

  def legacy_scope
    q = legacy_q
    fail_with!('Escribe el texto a buscar o elige un criterio.') if q.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
    base_scope.where('name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q OR identifier ILIKE :q',
                     q: pattern)
  end

  # Columnas planas del contacto. `country`/`city` viven en additional_attributes.
  def column_scope(field)
    case field
    when 'country', 'city' then json_attr_scope('additional_attributes', field)
    when 'name', 'email', 'phone_number', 'identifier' then text_column_scope(field)
    else fail_with!("Criterio de contacto no reconocido: \"#{field}\".")
    end
  end

  def text_column_scope(column)
    return presence_scope(column) if unary?

    require_value!
    return base_scope.where("#{column} = ?", value) if operator == 'equals'
    return base_scope.where.not("#{column} = ?", value) if operator == 'not_equals'
    return base_scope.where.not("#{column} ILIKE ?", "%#{like(value)}%") if operator == 'not_contains'

    base_scope.where("#{column} ILIKE ?", ilike_pattern)
  end

  # Patrón ILIKE según el operador parcial (contiene / empieza / termina).
  def ilike_pattern
    case operator
    when 'starts_with' then "#{like(value)}%"
    when 'ends_with' then "%#{like(value)}"
    else "%#{like(value)}%"
    end
  end

  def presence_scope(column)
    if operator == 'empty'
      base_scope.where("#{column} IS NULL OR #{column} = ''")
    else
      base_scope.where("#{column} IS NOT NULL AND #{column} <> ''")
    end
  end

  def json_attr_scope(jsonb_column, key)
    col = Arel.sql("contacts.#{jsonb_column}->>#{ActiveRecord::Base.connection.quote(key)}")
    require_value! unless unary?
    case operator
    when 'equals' then base_scope.where("#{col} = ?", value)
    when 'not_equals' then base_scope.where("#{col} IS DISTINCT FROM ?", value)
    when 'empty' then base_scope.where("#{col} IS NULL OR #{col} = ''")
    when 'not_empty' then base_scope.where("#{col} IS NOT NULL AND #{col} <> ''")
    else base_scope.where("#{col} ILIKE ?", "%#{like(value)}%")
    end
  end

  def custom_attr_scope(key)
    json_attr_scope('custom_attributes', key)
  end

  # Empresa: por id (lista) o vacío/no vacío.
  def company_scope
    case operator
    when 'empty' then base_scope.where(company_id: nil)
    when 'not_empty' then base_scope.where.not(company_id: nil)
    when 'not_in' then require_value! || base_scope.where.not(company_id: value_list)
    else require_value! || base_scope.where(company_id: value_list)
    end
  end

  # Etiqueta: reutiliza el tagging del contacto (Labelable → acts_as_taggable_on
  # :labels). Se resuelve a ids y se re-consulta para poder encadenar `includes`.
  def label_scope
    require_value!
    any = operator != 'not_in'
    ids = account.contacts.tagged_with(value_list, on: :labels, any: any).pluck(:id)
    return base_scope.where.not(id: ids) if operator == 'not_in'

    base_scope.where(id: ids)
  end

  # --- Helpers ---

  def unary?
    %w[empty not_empty].include?(operator)
  end

  def require_value!
    fail_with!('Este criterio necesita un valor para buscar.') if value.blank?
    false
  end

  def value_list
    value.split(',').map(&:strip).compact_blank
  end

  def like(text)
    ActiveRecord::Base.sanitize_sql_like(text)
  end
end
