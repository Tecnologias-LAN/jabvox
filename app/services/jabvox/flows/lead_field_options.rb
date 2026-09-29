# frozen_string_literal: true

# Kinds de opciones que describen los CAMPOS de un lead. Viven aparte porque los
# tres comparten la misma lectura de columnas personalizadas.
module Jabvox::Flows::LeadFieldOptions
  # Campos fijos del mapa plano de un lead. Las claves son las de
  # `BulkWhatsappDispatchService#lead_fields`, para que un mapa de variables sea
  # intercambiable entre el módulo de envíos masivos y los flujos.
  LEAD_FIXED_FIELDS = [
    ['nombre', 'Nombre del contacto'], ['numero', 'Número de WhatsApp (destino)'],
    %w[email Email], %w[telefono Teléfono], %w[identificador Identificador],
    %w[country País], %w[campaign Campaña], %w[afiliado Afiliado],
    ['assignee_name', 'Agente asignado (nombre)'], ['lead_number', 'Número de lead']
  ].freeze

  # --------------------------- Campos de lead --------------------------------

  def opt_lead_custom_fields(_params)
    lead_custom_columns.map do |c|
      option(c.name_jabvox, c.label_jabvox.presence || c.name_jabvox,
             'type' => c.column_type_jabvox, 'options' => c.options_jabvox,
             'required' => c.required_jabvox)
    end
  end

  def opt_lead_field_keys(_params)
    fixed = LEAD_FIXED_FIELDS.map do |value, label|
      option(value, label, 'group' => 'lead', 'custom' => false)
    end
    custom = lead_custom_columns.map do |c|
      option("custom:#{c.name_jabvox}", c.label_jabvox.presence || c.name_jabvox,
             'group' => 'custom', 'custom' => true, 'type' => c.column_type_jabvox)
    end
    fixed + custom
  end

  # Campos filtrables del modo "Condiciones múltiples". Solo se ofrecen los
  # campos PERSONALIZADOS porque es lo único que el nodo evalúa de verdad
  # (`LeadSearchNode` compara sobre `custom_fields_jabvox`): ofrecer más sería
  # ofrecer filtros que devolverían siempre vacío.
  def opt_lead_filter_fields(_params)
    lead_custom_columns.map do |c|
      data_type = filter_data_type(c.column_type_jabvox)
      option(c.name_jabvox, c.label_jabvox.presence || c.name_jabvox,
             'dataType' => data_type, 'operators' => Jabvox::Flows::FilterOperators.for(data_type),
             'values' => Array(c.options_jabvox).map(&:to_s),
             'columnType' => c.column_type_jabvox, 'group' => 'custom')
    end
  end

  private

  # Columnas de la tabla personalizada de leads de la cuenta.
  def lead_custom_columns
    @lead_custom_columns ||= begin
      table = JabvoxCustomTable.where(account_id: @account.id).for_contacts.first
      table ? table.jabvox_custom_columns.order(:position_jabvox).to_a : []
    end
  end

  def filter_data_type(column_type)
    case column_type.to_s
    when 'number', 'integer', 'decimal', 'currency' then 'number'
    when 'boolean', 'checkbox' then 'boolean'
    when 'select', 'multiselect' then 'list'
    else 'text'
    end
  end
end
