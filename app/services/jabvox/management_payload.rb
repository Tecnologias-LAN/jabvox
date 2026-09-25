# frozen_string_literal: true

# Saneamiento del bloque `content_attributes` de una gestión tal como lo construye el
# frontend (`buildManagementContentAttributes`).
#
# Vive aparte del controlador porque lo que llega es entrada del cliente que acaba en un
# jsonb sin esquema: solo se guardan las claves conocidas y los valores se recortan, para
# que nadie pueda inflar la columna ni meter estructuras arbitrarias.
class Jabvox::ManagementPayload
  ATTRIBUTE_KEYS = %i[
    jabvox_management_state_id jabvox_management_state_name jabvox_management_state_group
    jabvox_management_state_color jabvox_management_note_mode jabvox_management_managed
    jabvox_management_contact jabvox_management_effective_contact jabvox_management_advisory
    jabvox_management_service_type jabvox_management_positivity_level jabvox_call_source
  ].freeze

  MAX_LABEL = 255
  MAX_TYPE = 50
  MAX_VALUE = 2000
  MAX_LIST_VALUE = 500
  MAX_ANSWERS = 100

  def initialize(raw)
    @raw = raw
  end

  def to_h
    return {} if @raw.blank?

    permitted = @raw.permit(*ATTRIBUTE_KEYS, jabvox_management_answers: {}).to_h
    permitted['jabvox_management_answers'] = answers
    permitted
  end

  private

  # Las respuestas llegan como lista de {question_id,label,type,value}; `value` puede ser
  # texto, booleano o lista.
  def answers
    list = @raw[:jabvox_management_answers]
    return [] unless list.respond_to?(:map)

    Array(list).first(MAX_ANSWERS).filter_map { |a| answer_row(a) }
  end

  def answer_row(raw_answer)
    hash = raw_answer.respond_to?(:to_unsafe_h) ? raw_answer.to_unsafe_h : raw_answer
    return unless hash.is_a?(Hash)

    hash = hash.stringify_keys
    { 'question_id' => hash['question_id'],
      'label' => hash['label'].to_s.first(MAX_LABEL),
      'type' => hash['type'].to_s.first(MAX_TYPE),
      'value' => answer_value(hash['value']) }
  end

  def answer_value(value)
    return value.map { |v| v.to_s.first(MAX_LIST_VALUE) } if value.is_a?(Array)

    value.to_s.first(MAX_VALUE)
  end
end
