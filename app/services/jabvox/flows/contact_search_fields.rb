# frozen_string_literal: true

# CRITERIOS de búsqueda de contactos para el nodo "Buscar Contacto". Cada criterio
# declara en su `meta` cómo pedir el valor: `valueType` (text/select/date/number),
# `optionsSource` del desplegable cuando el valor es una lista conocida (empresa,
# etiqueta, atributo-lista), y los `operators` admitidos para su tipo. El editor usa
# ese meta para pintar UN solo campo de valor que se adapta al criterio elegido,
# igual que las automatizaciones básicas de Chatwoot. Nada se escribe a mano: todo
# sale de la cuenta.
#
# Vive aparte de OptionsService para no engordar esa clase (son varias piezas que
# solo este kind usa), igual que LeadFieldOptions.
module Jabvox::Flows::ContactSearchFields
  # Campos planos del contacto: todos texto, operadores de texto.
  CONTACT_TEXT_FIELDS = [
    %w[name Nombre], %w[email Email], %w[phone_number Teléfono],
    %w[identifier Identificador], %w[country País], %w[city Ciudad]
  ].freeze

  def opt_contact_search_fields(_params)
    contact_fixed_criteria + contact_company_criterion + contact_label_criterion +
      contact_custom_attr_criteria
  end

  private

  def contact_fixed_criteria
    ops = Jabvox::Flows::FilterOperators.for('text')
    CONTACT_TEXT_FIELDS.map do |value, label|
      option(value, label, 'valueType' => 'text', 'operators' => ops)
    end
  end

  # Empresa: el valor es un desplegable de las empresas de la cuenta. Vacío si el
  # módulo de empresas no está activo (no tiene sentido ofrecer el criterio).
  def contact_company_criterion
    return [] unless @account.feature_enabled?('companies')

    [option('company', 'Empresa',
            'valueType' => 'select', 'optionsSource' => 'companies',
            'operators' => Jabvox::Flows::FilterOperators.for('list'))]
  end

  # Etiqueta: el valor es un desplegable de las etiquetas de la cuenta.
  def contact_label_criterion
    [option('label', 'Etiqueta',
            'valueType' => 'select', 'optionsSource' => 'labels',
            'operators' => Jabvox::Flows::FilterOperators.for('list'))]
  end

  # Atributos personalizados del contacto: cada uno con su tipo y operadores, y
  # un desplegable cuando el atributo es una lista cerrada.
  def contact_custom_attr_criteria
    @account.custom_attribute_definitions.where(attribute_model: :contact_attribute)
            .order(:attribute_display_name).map do |attr|
      data_type = contact_attr_data_type(attr.attribute_display_type)
      option("custom:#{attr.attribute_key}",
             attr.attribute_display_name.presence || attr.attribute_key,
             'valueType' => contact_attr_value_type(data_type),
             'operators' => Jabvox::Flows::FilterOperators.for(data_type),
             'group' => 'custom', 'values' => Array(attr.attribute_values).map(&:to_s))
    end
  end

  def contact_attr_data_type(display_type)
    case display_type.to_s
    when 'number' then 'number'
    when 'checkbox' then 'boolean'
    when 'list' then 'list'
    when 'date' then 'date'
    else 'text'
    end
  end

  def contact_attr_value_type(data_type)
    case data_type
    when 'number' then 'number'
    when 'date' then 'date'
    when 'list', 'boolean' then 'select'
    else 'text'
    end
  end
end
