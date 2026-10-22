# frozen_string_literal: true

# Jabvox: evaluacion de la condicion "tipo de contenido del mensaje"
# (attachment_type) de las automations. No es un filtro SQL: mira los adjuntos del
# mensaje del evento (message_created) y decide si contiene cierto tipo.
#
# Tipos (del enum Attachment#file_type): image, audio, video, file. Ademas el valor
# especial 'text' = mensaje SIN adjuntos (solo texto). Operadores: contains /
# does_not_contain. Se evalua en Ruby sobre @options[:message], que message_created
# ya trae disponible, igual que la franja horaria (ver CurrentTimeCondition).
module AutomationRules::AttachmentTypeCondition
  ATTACHMENT_TYPE_KEY = 'attachment_type'
  # Tipos de adjunto evaluables + 'text' (sin adjunto). Se validan contra esta lista
  # para no depender de que el enum traiga tipos que la UI no ofrece.
  SUPPORTED_TYPES = %w[text image audio video file].freeze
  ATTACHMENT_OPERATORS = %w[contains does_not_contain].freeze

  def attachment_type_attribute?(query_hash)
    query_hash['attribute_key'] == ATTACHMENT_TYPE_KEY
  end

  # Clasifica una condicion evaluada en Ruby (franja horaria o tipo de adjunto):
  # :skip si se cumple (no aporta SQL), :fail si no, :sql si debe ir al WHERE normal.
  # Centraliza aqui la decision para no inflar el ConditionsFilterService.
  def ruby_condition_outcome(query_hash)
    return current_time_condition?(query_hash) ? :skip : :fail if current_time_attribute?(query_hash)
    return attachment_type_condition?(query_hash) ? :skip : :fail if attachment_type_attribute?(query_hash)

    :sql
  end

  # True solo cuando la condicion es de tipo de adjunto Y se cumple (para saltarla
  # del SQL). Si es de este tipo pero no se cumple, devuelve false y el loop corta la
  # regla via attachment_type_attribute?.
  def attachment_type_condition?(query_hash)
    attachment_type_attribute?(query_hash) && attachment_type_condition_met?(query_hash)
  end

  def attachment_type_condition_met?(query_hash)
    wanted = wanted_type(query_hash)
    return false if wanted.nil?

    present = message_has_type?(wanted)
    query_hash['filter_operator'].to_s == 'does_not_contain' ? !present : present
  end

  private

  # El tipo elegido en la UI. Acepta string suelto o lista (toma el primero), y el
  # objeto { id: 'image' } que arma el dropdown.
  def wanted_type(query_hash)
    raw = query_hash['values']
    raw = raw.first if raw.is_a?(Array)
    raw = raw['id'] if raw.is_a?(Hash)
    value = raw.to_s.strip.downcase
    SUPPORTED_TYPES.include?(value) ? value : nil
  end

  def message_has_type?(wanted)
    message = @options[:message]
    return false if message.blank?

    # 'text' = mensaje de solo texto: sin ningun adjunto.
    return message.attachments.empty? if wanted == 'text'

    message.attachments.any? { |att| att.file_type.to_s == wanted }
  end
end
