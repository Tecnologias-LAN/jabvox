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
  # horaria en Ruby y acumula el resto como filtro SQL. Las condiciones de nivel
  # superior se unen por su query_operator (AND/OR), así que una condición de hora
  # que no se cumple NO corta la regla: aporta su verdad/falsedad al WHERE y deja que
  # el OR/AND decida. Antes cortaba con `return false`, lo que convertía todo OR entre
  # franjas horarias en un AND (bug: "(mañana O tarde)" sin grupo no disparaba nunca).
  def build_filters
    # Índice GLOBAL de condición: los binds (:value_N) deben ser únicos aunque las
    # condiciones vivan dentro de grupos. No se reinicia por grupo.
    @condition_index = 0
    @rule.conditions.each do |query_hash|
      if group?(query_hash)
        build_group_filter(query_hash)
      else
        apply_single_condition(query_hash)
      end
    end
    true
  end

  # Procesa una condición plana del nivel superior.
  #   - attribute_changed: se posterga a su filtro propio.
  #   - condición Ruby (franja horaria / adjunto): NO corta; aporta su verdad como
  #     fragmento SQL (1=1 cumplida / 1=0 no cumplida) con su query_operator, para que
  #     el OR/AND entre condiciones la combine correctamente.
  #   - condición SQL normal: su fragmento al WHERE.
  def apply_single_condition(query_hash)
    @attribute_changed_query_filter << query_hash and return true if query_hash['filter_operator'] == 'attribute_changed'

    case ruby_condition_outcome(query_hash)
    when :skip then append_ruby_truth(query_hash, true)
    when :fail then append_ruby_truth(query_hash, false)
    else
      apply_filter(query_hash, @condition_index) # condicion SQL normal
      @condition_index += 1
    end
    true
  end

  # Emite la verdad de una condición Ruby como SQL (1=1 / 1=0) seguida de su
  # query_operator, igual que una condición SQL. Así una franja horaria participa en el
  # OR/AND del WHERE en vez de cortar la regla. El query_operator se sanea a AND/OR/''
  # (el último no lleva); `sanitize_dangling_operators` limpia cualquier sobrante.
  def append_ruby_truth(query_hash, truthy)
    op = query_hash['query_operator'].to_s.strip.upcase
    op = '' unless %w[AND OR].include?(op)
    @query_string += " #{truthy ? '1=1' : '1=0'} #{op} "
  end

  # Construye el filtro de un GRUPO (paréntesis): "( hija1 OP hija2 ... )" unido a lo
  # siguiente por query_operator, para expresar "A AND (B OR C)".
  #
  # Dentro de un grupo cada hija es de UNA de estas clases (se clasifica por tipo,
  # cada una en su rama — no se colapsa todo a un booleano a ciegas):
  #   - :sql   → status, labels, prioridad... produce un fragmento de WHERE.
  #   - :skip  → condición Ruby (franja horaria / tipo de adjunto) que SÍ se cumple.
  #   - :fail  → condición Ruby que NO se cumple.
  # Las hijas Ruby (:skip/:fail) se combinan con el child_operator del grupo, NO
  # cortan el grupo entero. Antes, una hija Ruby :fail devolvía false y tumbaba el
  # grupo aunque el operador fuese OR (bug real: "(mañana O tarde)" no disparaba en la
  # mañana porque la rama "tarde" era falsa).
  def build_group_filter(group_hash)
    operator = group_child_operator(group_hash) # 'AND' | 'OR'
    sql_pieces = []
    ruby_flags = []

    group_children(group_hash).each do |child|
      case ruby_condition_outcome(child)
      when :sql
        fragment = capture_child_sql_fragment(child)
        sql_pieces << fragment if fragment.present?
      when :skip
        ruby_flags << true  # condición Ruby cumplida
      when :fail
        ruby_flags << false # condición Ruby no cumplida
      end
    end

    emit_group_sql(sql_pieces, ruby_flags, operator, group_hash)
  end

  # Combina el lado SQL y el lado Ruby del grupo según el operador y lo acumula en el
  # WHERE. El grupo NUNCA corta la evaluación: aporta su verdad al @query_string con el
  # query_operator que lo une a lo siguiente, igual que una condición plana. Así un grupo
  # falso unido por OR a nivel raíz no tumba las demás condiciones (bug: "(solo-tarde) OR
  # status=open" por la mañana con status=open no disparaba porque el grupo Ruby falso
  # cortaba antes de evaluar el status).
  def emit_group_sql(sql_pieces, ruby_flags, operator, group_hash)
    # Lado Ruby combinado: OR = alguna se cumple; AND = todas se cumplen. Sin hijas
    # Ruby, es neutro (no condiciona).
    ruby_ok = ruby_flags.empty? || (operator == 'AND' ? ruby_flags.all? : ruby_flags.any?)

    if sql_pieces.empty?
      # Grupo sin SQL (p. ej. solo franjas horarias): su booleano Ruby se expresa como
      # 1=1 / 1=0 con el operador del grupo hacia lo siguiente, para participar en el
      # OR/AND del nivel raíz en vez de cortar.
      @query_string += " #{ruby_ok ? '1=1' : '1=0'} #{safe_group_operator(group_hash)} "
      return
    end

    # Hay SQL. Representamos el booleano Ruby como una verdad/falsedad SQL (1=1 / 1=0),
    # igual que el filtro de labels ya usa "1=0" para un valor imposible. Así el
    # operador del grupo (AND/OR) combina ambos lados de forma consistente dentro del
    # WHERE, sin reinterpretar el SQL en Ruby.
    sql_pieces << (ruby_ok ? '1=1' : '1=0') unless ruby_flags.empty?

    @query_string += " (#{sql_pieces.join(" #{operator} ")}) #{safe_group_operator(group_hash)} "
  end

  # Ejecuta una hija SQL del grupo capturando SOLO el SQL que produce (aislándolo de
  # @query_string) y quitándole su query_operator final, para no tocar los AND
  # internos de una subconsulta (ej. labels NOT IN (... AND ...)).
  def capture_child_sql_fragment(child)
    saved = @query_string
    @query_string = ''
    apply_single_condition(child)
    fragment = @query_string
    @query_string = saved
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
      # "La empresa del contacto NO es X" debe incluir también a los contactos SIN
      # empresa (company_id NULL). Con el LEFT JOIN, `company_id NOT IN (:v)` da NULL
      # (no TRUE) para esos contactos, así que la regla no dispararía para quien no
      # tiene empresa. Se añade el OR explícito, igual que en el filtro de labels.
      if attribute_key == 'company_id' && query_hash['filter_operator'] == 'not_equal_to'
        " (contacts.#{attribute_key} #{filter_operator_value} OR contacts.#{attribute_key} IS NULL) #{query_operator} "
      else
        " contacts.#{attribute_key} #{filter_operator_value} #{query_operator} "
      end
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
