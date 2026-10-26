require 'json'

class AutomationRules::ConditionsFilterService < FilterService # rubocop:disable Metrics/ClassLength
  include AutomationRules::CurrentTimeCondition
  include AutomationRules::AttachmentTypeCondition
  include AutomationRules::AttributeChangedFilter

  ATTRIBUTE_MODEL = 'contact_attribute'.freeze

  def initialize(rule, conversation = nil, options = {})
    super([], nil)
    # assign rule, conversation and account to instance variables
    @rule = rule
    @conversation = conversation
    @account = conversation.account

    # setup filters from json file
    file = File.read('./lib/filters/filter_keys.yml')
    @filters = YAML.safe_load(file)

    @conversation_filters = @filters['conversations']
    @contact_filters = @filters['contacts']
    @message_filters = @filters['messages']

    @options = options
    @changed_attributes = options[:changed_attributes]
  end

  def perform
    return false unless rule_valid?

    @attribute_changed_query_filter = []

    # build_filters arma el @query_string SQL y evalua en Ruby la franja horaria;
    # devuelve false si una condicion de hora no se cumple (la regla no matchea).
    return false unless build_filters

    # Las condiciones current_time no aportan SQL; al saltarlas puede quedar un
    # operador AND/OR colgando o doble. Se normaliza para no romper el where.
    @query_string = sanitize_dangling_operators(@query_string)

    # Si la unica condicion era current_time (ya evaluada en Ruby y cumplida),
    # @query_string queda vacio: no hay filtro SQL que aplicar, la regla matchea.
    records = @query_string.blank? ? base_relation : base_relation.where(@query_string, @filter_values.with_indifferent_access)
    records = perform_attribute_changed_filter(records) if @attribute_changed_query_filter.any?

    records.any?
  rescue StandardError => e
    Rails.logger.error "Error in AutomationRules::ConditionsFilterService: #{e.message}"
    Rails.logger.info "AutomationRules::ConditionsFilterService failed while processing rule #{@rule.id} for conversation #{@conversation.id}"
    false
  end

  # Limpia operadores AND/OR que queden colgando o duplicados cuando una condicion
  # current_time (que no aporta SQL) se salta al inicio, en medio o al final.
  def sanitize_dangling_operators(sql)
    sql.gsub(/\s+(AND|OR)\s+(AND|OR)\s+/i, ' \1 ')
       .sub(/\A\s*(AND|OR)\s+/i, '')
       .sub(/\s+(AND|OR)\s*\z/i, '')
       .strip
  end

  # Itera las condiciones de la regla: separa attribute_changed, evalua la franja
  # horaria en Ruby y acumula el resto como filtro SQL. Devuelve false si una
  # condicion de hora no se cumple.
  def build_filters
    # Índice GLOBAL de condición: los binds (:value_N) deben ser únicos aunque las
    # condiciones vivan dentro de grupos. No se reinicia por grupo.
    @condition_index = 0
    @rule.conditions.each do |query_hash|
      if group?(query_hash)
        return false unless build_group_filter(query_hash)
      else
        return false unless apply_single_condition(query_hash)
      end
    end
    true
  end

  # Procesa una condición plana (legacy). Devuelve false solo si una condición Ruby
  # (franja horaria) no se cumple y por tanto la regla no matchea.
  def apply_single_condition(query_hash)
    @attribute_changed_query_filter << query_hash and return true if query_hash['filter_operator'] == 'attribute_changed'

    case ruby_condition_outcome(query_hash)
    when :skip then true          # condicion Ruby cumplida: no aporta SQL
    when :fail then false         # condicion Ruby no cumplida: la regla no matchea
    else
      apply_filter(query_hash, @condition_index) # condicion SQL normal
      @condition_index += 1
      true
    end
  end

  # Emite "( hija1 OP hija2 ... ) query_operator" acumulando el SQL de cada hija por
  # separado, para expresar "A AND (B OR C)". child_operator une las hijas;
  # query_operator une el grupo con lo siguiente. Las condiciones Ruby (franja horaria)
  # dentro del grupo se evalúan igual: si una falla, la regla no matchea (coherente con
  # el AND global). Devuelve false si una hija Ruby no se cumple.
  def build_group_filter(group_hash)
    pieces = []
    group_children(group_hash).each do |child|
      fragment = capture_child_fragment(child) { |ok| return false unless ok }
      pieces << fragment if fragment.present?
    end
    return true if pieces.empty?

    @query_string += " (#{pieces.join(" #{group_child_operator(group_hash)} ")}) #{safe_group_operator(group_hash)} "
    true
  end

  # Ejecuta una hija del grupo capturando SOLO el SQL que produce (aislándolo de
  # @query_string) y quitándole su query_operator final, para no tocar los AND
  # internos de una subconsulta (ej. labels NOT IN (... AND ...)). Cede el resultado
  # de evaluación (ok) al bloque para que el llamador pueda cortar si una hija falla.
  def capture_child_fragment(child)
    saved = @query_string
    @query_string = ''
    ok = apply_single_condition(child)
    fragment = @query_string
    @query_string = saved
    yield ok
    strip_trailing_operator(fragment.strip)
  end

  def rule_valid?
    is_valid = AutomationRules::ConditionValidationService.new(@rule).perform
    Rails.logger.info "Automation rule condition validation failed for rule id: #{@rule.id}" unless is_valid
    @rule.authorization_error! unless is_valid

    is_valid
  end

  def filter_operation(query_hash, current_index)
    if query_hash[:filter_operator] == 'starts_with'
      @filter_values["value_#{current_index}"] = "#{string_filter_values(query_hash)}%"
      like_filter_string(query_hash[:filter_operator], current_index)
    else
      super
    end
  end

  def apply_filter(query_hash, current_index)
    conversation_filter = @conversation_filters[query_hash['attribute_key']]
    contact_filter = @contact_filters[query_hash['attribute_key']]
    message_filter = @message_filters[query_hash['attribute_key']]

    if conversation_filter
      @query_string += conversation_query_string('conversations', conversation_filter, query_hash.with_indifferent_access, current_index)
    elsif contact_filter
      @query_string += contact_query_string(contact_filter, query_hash.with_indifferent_access, current_index)
    elsif message_filter
      @query_string += message_query_string(message_filter, query_hash.with_indifferent_access, current_index)
    elsif custom_attribute(query_hash['attribute_key'], @account, query_hash['custom_attribute_type'])
      # send table name according to attribute key right now we are supporting contact based custom attribute filter
      @query_string += custom_attribute_query(query_hash.with_indifferent_access, query_hash['custom_attribute_type'], current_index)
    end
  end

  def message_query_string(current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']

    attribute_key = 'processed_message_content' if attribute_key == 'content'
    attribute_key = 'private' if attribute_key == 'private_note'

    filter_operator_value = filter_operation(query_hash, current_index)

    case current_filter['attribute_type']
    when 'standard'
      if current_filter['data_type'] == 'text'
        " LOWER(messages.#{attribute_key}) #{filter_operator_value} #{query_operator} "
      else
        " messages.#{attribute_key} #{filter_operator_value} #{query_operator} "
      end
    end
  end

  # This will be used in future for contact automation rule
  def contact_query_string(current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']

    filter_operator_value = filter_operation(query_hash, current_index)

    case current_filter['attribute_type']
    when 'additional_attributes'
      " contacts.additional_attributes ->> '#{attribute_key}' #{filter_operator_value} #{query_operator} "
    when 'standard'
      " contacts.#{attribute_key} #{filter_operator_value} #{query_operator} "
    end
  end

  def conversation_query_string(table_name, current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']
    filter_operator_value = filter_operation(query_hash, current_index)

    case current_filter['attribute_type']
    when 'additional_attributes'
      " #{table_name}.additional_attributes ->> '#{attribute_key}' #{filter_operator_value} #{query_operator} "
    when 'standard'
      if attribute_key == 'labels'
        build_label_query_string(query_hash, current_index, query_operator)
      else
        " #{table_name}.#{attribute_key} #{filter_operator_value} #{query_operator} "
      end
    end
  end

  def build_label_query_string(query_hash, current_index, query_operator)
    case query_hash['filter_operator']
    when 'equal_to'
      return " 1=0 #{query_operator} " if query_hash['values'].blank?

      value_placeholder = "value_#{current_index}"
      @filter_values[value_placeholder] = query_hash['values'].first
      " tags.name = :#{value_placeholder} #{query_operator} "
    when 'not_equal_to'
      return " 1=0 #{query_operator} " if query_hash['values'].blank?

      value_placeholder = "value_#{current_index}"
      @filter_values[value_placeholder] = query_hash['values'].first
      "#{label_not_equal_sql(value_placeholder)} #{query_operator} "
    when 'is_present'
      " tags.id IS NOT NULL #{query_operator} "
    when 'is_not_present'
      " tags.id IS NULL #{query_operator} "
    else
      " tags.id #{filter_operation(query_hash, current_index)} #{query_operator} "
    end
  end

  private

  # "No igual a X" debe ser verdadero cuando la conversación NO tiene la etiqueta X
  # — ya sea porque no tiene NINGUNA etiqueta, o porque tiene otras distintas de X.
  # Con el LEFT JOIN, `tags.name != :x` fallaba para las conversaciones SIN
  # etiquetas (tags.name = NULL => NULL != 'x' = NULL, no TRUE), así que la regla no
  # disparaba para clientes nuevos sin etiquetar. Usamos una subconsulta a nivel de
  # conversación (igual que el filtro de conversaciones) para que ambos casos
  # coincidan. El placeholder va sanitizado por el bind de @filter_values.
  def label_not_equal_sql(value_placeholder)
    'conversations.id NOT IN (' \
      'SELECT taggings.taggable_id FROM taggings ' \
      'INNER JOIN tags ON taggings.tag_id = tags.id ' \
      "WHERE taggings.taggable_type = 'Conversation' AND tags.name = :#{value_placeholder})"
  end

  def base_relation
    records = Conversation.where(id: @conversation.id).joins(
      'LEFT OUTER JOIN contacts on conversations.contact_id = contacts.id'
    ).joins(
      'LEFT OUTER JOIN messages on messages.conversation_id = conversations.id'
    )

    # Only add label joins when label conditions exist
    if label_conditions?
      records = records.joins(
        'LEFT OUTER JOIN taggings ON taggings.taggable_id = conversations.id AND taggings.taggable_type = \'Conversation\''
      ).joins(
        'LEFT OUTER JOIN tags ON taggings.tag_id = tags.id'
      )
    end

    records = records.where(messages: { id: @options[:message].id }) if @options[:message].present?
    records
  end

  # Detecta condiciones de etiquetas también DENTRO de grupos, para añadir el JOIN
  # a taggings/tags cuando corresponda (si no, el SQL de labels del grupo no resuelve).
  def label_conditions?
    flatten_conditions(@rule.conditions).any? { |condition| group_attr(condition, :attribute_key) == 'labels' }
  end
end
