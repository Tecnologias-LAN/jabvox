require 'json'

class FilterService # rubocop:disable Metrics/ClassLength
  include Filters::FilterHelper
  include Filters::CustomAttributeFilterHelper
  include Filters::ConditionGroupSupport
  include CustomExceptions::CustomFilter

  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze
  ATTRIBUTE_TYPES = {
    date: 'date', text: 'text', number: 'numeric', link: 'text', list: 'text', checkbox: 'boolean'
  }.with_indifferent_access

  def initialize(params, user)
    @params = params
    @user = user
    file = File.read('./lib/filters/filter_keys.yml')
    @filters = YAML.safe_load(file)
    @query_string = ''
    @filter_values = {}
  end

  def perform; end

  # Operador -> método que arma su fragmento SQL y deja el valor en @filter_values.
  FILTER_OPERATIONS = {
    'equal_to' => :equality_filter_query, 'not_equal_to' => :equality_filter_query,
    'contains' => :ilike_filter_query, 'does_not_contain' => :ilike_filter_query,
    'starts_with' => :starts_with_filter_query,
    'is_present' => :presence_filter_query, 'is_not_present' => :presence_filter_query,
    'is_greater_than' => :lt_gt_filter_query, 'is_less_than' => :lt_gt_filter_query,
    'days_before' => :days_before_filter_query
  }.freeze

  def filter_operation(query_hash, current_index)
    handler = FILTER_OPERATIONS[query_hash[:filter_operator]] || :default_filter_query
    send(handler, query_hash, current_index)
  end

  def equality_filter_query(query_hash, current_index)
    @filter_values["value_#{current_index}"] = filter_values(query_hash)
    equals_to_filter_string(query_hash[:filter_operator], current_index)
  end

  def ilike_filter_query(query_hash, current_index)
    @filter_values["value_#{current_index}"] = values_for_ilike(query_hash)
    ilike_filter_string(query_hash[:filter_operator], current_index)
  end

  def presence_filter_query(query_hash, current_index)
    @filter_values["value_#{current_index}"] = query_hash[:filter_operator] == 'is_present' ? 'IS NOT NULL' : 'IS NULL'
  end

  def default_filter_query(query_hash, current_index)
    @filter_values["value_#{current_index}"] = filter_values(query_hash).to_s
    "= :value_#{current_index}"
  end

  def filter_values(query_hash)
    attribute_key = query_hash['attribute_key']
    values = query_hash['values']

    return conversation_status_values(values) if attribute_key == 'status'
    return conversation_priority_values(values) if attribute_key == 'priority'
    return message_type_values(values) if attribute_key == 'message_type'
    return downcase_array_values(values) if attribute_key == 'content'

    case_insensitive_values(query_hash)
  end

  def downcase_array_values(values)
    values.map(&:downcase)
  end

  def case_insensitive_values(query_hash)
    if @custom_attribute_type.present? && query_hash['values'][0].is_a?(String)
      string_filter_values(query_hash)
    else
      query_hash['values']
    end
  end

  # `starts_with` lo ofrece el YAML (teléfono) pero no estaba cableado en filter_operation:
  # caía al `else`, que hace igualdad exacta, así que nunca encontraba nada.
  def starts_with_filter_query(query_hash, current_index)
    @filter_values["value_#{current_index}"] = values_for_starts_with(query_hash)
    "ILIKE ANY (ARRAY[:value_#{current_index}])"
  end

  # Prefijo para `starts_with`: solo comodín al final.
  def values_for_starts_with(query_hash)
    Array(query_hash['values']).map { |item| "#{item.to_s.strip}%" }
  end

  def values_for_ilike(query_hash)
    if query_hash['values'].is_a?(Array)
      query_hash['values']
        .map { |item| "%#{item.strip}%" }
    else
      ["%#{query_hash['values'].strip}%"]
    end
  end

  def string_filter_values(query_hash)
    return query_hash['values'][0].downcase if query_hash['values'].is_a?(Array)

    query_hash['values'].downcase
  end

  def lt_gt_filter_query(query_hash, current_index)
    attribute_key = query_hash[:attribute_key]
    attribute_model = query_hash['custom_attribute_type'].presence || self.class::ATTRIBUTE_MODEL
    attribute_type = custom_attribute(attribute_key, @account, attribute_model).try(:attribute_display_type)
    attribute_data_type = self.class::ATTRIBUTE_TYPES[attribute_type] || standard_attribute_data_type(attribute_key)

    @filter_values["value_#{current_index}"] = coerce_lt_gt_value(
      query_hash['values'][0],
      attribute_data_type,
      attribute_key
    )
    operator = query_hash['filter_operator'] == 'is_less_than' ? '<' : '>'
    "#{operator} :value_#{current_index}"
  end

  def days_before_filter_query(query_hash, current_index)
    date = Time.zone.today - query_hash['values'][0].to_i.days
    # `to_unsafe_h` porque query_hash llega como ActionController::Parameters, que NO responde
    # a with_indifferent_access: sin esto el filtro "días antes" reventaba con 500.
    raw = query_hash.respond_to?(:to_unsafe_h) ? query_hash.to_unsafe_h : query_hash
    updated_query_hash = raw.with_indifferent_access.merge(
      values: [date.strftime],
      filter_operator: 'is_less_than'
    )

    lt_gt_filter_query(updated_query_hash, current_index)
  end

  def set_count_for_all_conversations
    [
      @conversations.assigned_to(@user).count,
      @conversations.unassigned.count,
      @conversations.count
    ]
  end

  def tag_filter_query(query_hash, current_index)
    model_name = filter_config[:entity]
    table_name = filter_config[:table_name]
    query_operator = query_hash[:query_operator]
    @filter_values["value_#{current_index}"] = filter_values(query_hash)

    tag_model_relation_query =
      "SELECT * FROM taggings WHERE taggings.taggable_id = #{table_name}.id AND taggings.taggable_type = '#{model_name}'"
    tag_query =
      "AND taggings.tag_id IN (SELECT tags.id FROM tags WHERE tags.name IN (:value_#{current_index}))"

    case query_hash[:filter_operator]
    when 'equal_to'
      "EXISTS (#{tag_model_relation_query} #{tag_query}) #{query_operator}"
    when 'not_equal_to'
      "NOT EXISTS (#{tag_model_relation_query} #{tag_query}) #{query_operator}"
    when 'is_present'
      "EXISTS (#{tag_model_relation_query}) #{query_operator}"
    when 'is_not_present'
      "NOT EXISTS (#{tag_model_relation_query}) #{query_operator}"
    end
  end

  private

  def standard_attribute_data_type(attribute_key)
    @filters.each_value do |section|
      return section.dig(attribute_key, 'data_type') if section.is_a?(Hash) && section.key?(attribute_key)
    end
    nil
  end

  def coerce_lt_gt_value(raw_value, attribute_data_type, attribute_key)
    case attribute_data_type
    when 'date'
      Date.iso8601(raw_value.to_s)
    when 'numeric'
      BigDecimal(raw_value.to_s)
    else
      raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: attribute_key)
    end
  rescue  ArgumentError, FloatDomainError, TypeError
    raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: attribute_key)
  end

  def equals_to_filter_string(filter_operator, current_index)
    return  "IN (:value_#{current_index})" if filter_operator == 'equal_to'

    "NOT IN (:value_#{current_index})"
  end

  def ilike_filter_string(filter_operator, current_index)
    return "ILIKE ANY (ARRAY[:value_#{current_index}])" if %w[contains].include?(filter_operator)

    "NOT ILIKE ALL (ARRAY[:value_#{current_index}])"
  end

  def like_filter_string(filter_operator, current_index)
    return "LIKE :value_#{current_index}" if %w[contains starts_with].include?(filter_operator)

    "NOT LIKE :value_#{current_index}"
  end

  # Construye el WHERE a partir del payload. Cada elemento del array puede ser:
  #  - una condición PLANA (formato legacy): { attribute_key, filter_operator, values, query_operator }
  #  - un GRUPO (nuevo): { type: 'group', query_operator, child_operator, conditions: [ ...planas... ] }
  # Un grupo se emite entre paréntesis uniendo sus hijas con child_operator (AND/OR),
  # lo que permite expresar "A AND (B OR C)". El formato plano sigue intacto
  # (retrocompatibilidad: reglas/filtros guardados antes siguen funcionando igual).
  def query_builder(model_filters)
    # Índice GLOBAL de condición, para que los placeholders de binds (:value_N) sean
    # únicos aunque las condiciones estén repartidas entre grupos y el nivel raíz.
    @condition_index = 0
    @params[:payload].each do |query_hash|
      fragment = if group?(query_hash)
                   build_group_query(model_filters, query_hash)
                 else
                   piece = build_condition_query(model_filters, query_hash, @condition_index).strip
                   @condition_index += 1
                   piece
                 end
      @query_string += " #{fragment}" if fragment.present?
    end
    base_relation.where(@query_string.strip, @filter_values.with_indifferent_access)
  end

  # Emite "( hija1 OP hija2 OP ... ) query_operator" para un grupo.
  # child_operator (AND/OR) une las condiciones DENTRO del grupo; query_operator
  # (AND/OR) une el grupo entero con lo que venga DESPUÉS (igual que una condición plana).
  def build_group_query(model_filters, group_hash)
    child_operator = group_child_operator(group_hash)
    group_operator = safe_group_operator(group_hash)

    pieces = group_children(group_hash).map { |child| group_child_fragment(model_filters, child) }.reject(&:blank?)
    return '' if pieces.empty?

    "(#{pieces.join(" #{child_operator} ")}) #{group_operator}".strip
  end

  # Fragmento SQL de una hija del grupo, sin su query_operator final (el grupo pone
  # el child_operator entre hijas), avanzando el índice global de binds.
  def group_child_fragment(model_filters, child)
    frag = strip_trailing_operator(build_condition_query(model_filters, child, @condition_index).strip)
    @condition_index += 1
    frag
  end

  def validate_query_operator
    @params[:payload].each do |query_hash|
      if group?(query_hash)
        # Defensa en profundidad: validar el operador del PROPIO nodo grupo (además
        # de normalizarlo en build_group_query) y el de cada hija.
        validate_single_condition(query_hash)
        group_children(query_hash).each { |child| validate_single_condition(child) }
      else
        validate_single_condition(query_hash)
      end
    end
  end
end
