class AutomationRules::ConditionValidationService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

  def initialize(rule)
    @rule = rule
    @account = rule.account

    file = File.read('./lib/filters/filter_keys.yml')
    @filters = YAML.safe_load(file)

    @conversation_filters = @filters['conversations']
    @contact_filters = @filters['contacts']
    @message_filters = @filters['messages']
  end

  def perform
    @rule.conditions.each do |condition|
      return false unless valid_condition?(condition) && valid_query_operator?(condition)
    end

    true
  end

  private

  def valid_query_operator?(condition)
    query_operator = condition['query_operator']

    return true if query_operator.nil?
    return true if query_operator.empty?

    %w[AND OR].include?(query_operator.upcase)
  end

  # Jabvox: franja horaria. No es un filtro SQL (no toca ninguna columna); se
  # evalua en Ruby comparando la hora actual contra un rango. Por eso vive fuera
  # de filter_keys.yml y se valida aqui como caso especial.
  CURRENT_TIME_OPERATORS = %w[is_between is_not_between].freeze
  # attachment_type: tipo de contenido del mensaje, evaluado en Ruby (no es SQL).
  # La UI ofrece los cuatro operadores de OPERATOR_TYPES_2, así que se aceptan todos:
  # equal_to se trata como contains y not_equal_to como does_not_contain (ver
  # AttachmentTypeCondition). Si solo se aceptaran contains/does_not_contain, una regla
  # guardada con "Igual a" fallaba la validación y se DESACTIVABA sola sin disparar.
  ATTACHMENT_TYPE_OPERATORS = %w[contains does_not_contain equal_to not_equal_to].freeze

  # Condiciones evaluadas en Ruby (no en filter_keys.yml) y sus operadores validos.
  RUBY_CONDITION_OPERATORS = {
    'current_time' => CURRENT_TIME_OPERATORS,
    'attachment_type' => ATTACHMENT_TYPE_OPERATORS
  }.freeze

  def valid_condition?(condition)
    key = condition['attribute_key']

    ruby_operators = RUBY_CONDITION_OPERATORS[key]
    return ruby_operators.include?(condition['filter_operator']) if ruby_operators

    conversation_filter = @conversation_filters[key]
    contact_filter = @contact_filters[key]
    message_filter = @message_filters[key]

    if conversation_filter || contact_filter || message_filter
      operation_valid?(condition, conversation_filter || contact_filter || message_filter)
    else
      custom_attribute_present?(key, condition['custom_attribute_type'])
    end
  end

  def operation_valid?(condition, filter)
    filter_operator = condition['filter_operator']

    # attribute changed is a special case
    return true if filter_operator == 'attribute_changed'

    filter['filter_operators'].include?(filter_operator)
  end

  def custom_attribute_present?(attribute_key, attribute_model)
    attribute_model = attribute_model.presence || self.class::ATTRIBUTE_MODEL

    @account.custom_attribute_definitions.where(
      attribute_model: attribute_model
    ).find_by(attribute_key: attribute_key).present?
  end
end
