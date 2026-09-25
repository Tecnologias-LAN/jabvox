# frozen_string_literal: true

# Convierte lo que manda el formulario de la ficha del contacto en valores del TIPO que
# declara cada columna personalizada.
#
# Existe porque el navegador manda todo como texto: una fecha llega como "2026-09-24", un
# booleano como "true" y un número como "42". Sin este paso el jsonb se llenaba de cadenas,
# y entonces ni los filtros ni los informes ni Analytics podían compararlas como fechas o
# como números.
#
# Dos garantías:
#   - solo entran claves que la cuenta tiene configuradas como campo personalizado, así que
#     el cliente no puede inyectar claves arbitrarias en el jsonb;
#   - el valor pasa por el `coerce` de SU columna, que rechaza lo que no encaja (una fecha
#     inválida, una opción que no está en la lista) en vez de guardarlo igualmente.
class Jabvox::CustomFieldsCoercion
  Error = Class.new(StandardError)

  MAX_STRING_LENGTH = 2000

  def initialize(account)
    @account = account
  end

  # Devuelve los campos ya existentes mezclados con los entrantes ya convertidos.
  # Lo que no venga en la petición se conserva: el historial del ciclo de vida, por
  # ejemplo, vive en este mismo jsonb y no lo manda el formulario.
  # Lanza Error si algún valor no encaja con su tipo.
  def merge_into(current, incoming)
    current ||= {}
    return current if incoming.blank?

    incoming = incoming.to_unsafe_h if incoming.respond_to?(:to_unsafe_h)
    coerced, errors = coerce(incoming.to_h)
    raise Error, errors.join('; ') if errors.any?

    current.merge(coerced)
  end

  private

  def coerce(incoming)
    columns = contact_columns.index_by(&:name_jabvox)
    coerced = {}
    errors = []

    incoming.each do |key, value|
      column = columns[key.to_s]
      next unless column # clave que no es campo personalizado de la cuenta: se descarta

      result, error = column.coerce(value)
      next errors << error if error

      coerced[key.to_s] = clamp(result)
    end

    [coerced, errors]
  end

  def contact_columns
    table = @account.jabvox_custom_tables.for_contacts.first
    table ? table.jabvox_custom_columns.ordered.to_a : []
  end

  # Tope de tamaño por valor, también dentro de las listas de un multiselect.
  def clamp(value)
    case value
    when String then value.first(MAX_STRING_LENGTH)
    when Array then value.map { |v| v.is_a?(String) ? v.first(MAX_STRING_LENGTH) : v }
    else value
    end
  end
end
