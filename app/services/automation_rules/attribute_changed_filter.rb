# frozen_string_literal: true

# Filtrado por condiciones `attribute_changed` (p. ej. "el estado cambió de X a
# Y"): no es un WHERE SQL simple, sino una interseccion/union de registros segun
# los cambios reales del evento. Se extrae del ConditionsFilterService para no
# inflarlo; depende de @attribute_changed_query_filter, @changed_attributes y
# base_relation, que define el service.
module AutomationRules::AttributeChangedFilter
  # If attribute_changed type filter is present perform this against array
  def perform_attribute_changed_filter(records)
    @attribute_changed_records = []
    current_attribute_changed_record = base_relation
    filter_based_on_attribute_change(records, current_attribute_changed_record)

    @attribute_changed_records.uniq
  end

  # Loop through attribute_changed_query_filter
  def filter_based_on_attribute_change(records, current_attribute_changed_record)
    @attribute_changed_query_filter.each do |filter|
      @changed_attributes = @changed_attributes.with_indifferent_access
      changed_attribute = @changed_attributes[filter['attribute_key']].presence

      # El atributo de la condición puede no estar entre los que cambiaron en este evento
      # (p. ej. la regla mira "estado cambió" pero el evento cambió otra cosa). En ese caso
      # `changed_attribute` es nil y `nil[0]` reventaría (NoMethodError), que el rescue de
      # ConditionsFilterService tragaba dejando la regla en false sin rastro. Se salta.
      next if changed_attribute.nil?

      from = filter.dig('values', 'from')
      to = filter.dig('values', 'to')
      if changed_attribute[0].in?(from) && changed_attribute[1].in?(to)
        @attribute_changed_records = attribute_changed_filter_query(filter, records, current_attribute_changed_record)
      end
      current_attribute_changed_record = @attribute_changed_records
    end
  end

  # We intersect with the record if query_operator-AND is present and union if query_operator-OR is present
  def attribute_changed_filter_query(filter, records, current_attribute_changed_record)
    if filter['query_operator'] == 'AND'
      @attribute_changed_records + (current_attribute_changed_record & records)
    else
      @attribute_changed_records + (current_attribute_changed_record | records)
    end
  end
end
