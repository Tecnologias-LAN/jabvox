# frozen_string_literal: true

# Tool nativa de Jabvox IA: permite fijar/actualizar mensajes de configuración
# del PROPIO asistente conversando en la zona de pruebas (playground). P. ej.
# "quiero que la despedida sea ...". Escribe SOLO en el asistente actual y SOLO
# desde el playground (nunca en conversaciones reales con clientes), con una
# whitelist de campos. Nunca borra otras claves de config (usa merge).
class Captain::Tools::UpdateConfigurationTool < Captain::Tools::BasePublicTool
  # Campos de texto que el asistente puede fijar desde el playground. Whitelist
  # estricta: el modelo no puede escribir claves arbitrarias en config.
  ALLOWED_FIELDS = {
    'despedida' => 'resolution_message',
    'bienvenida' => 'welcome_message',
    'mensaje_escalado' => 'handoff_message',
    'instrucciones' => 'instructions'
  }.freeze

  description 'Fija o actualiza un mensaje de configuración de ESTE asistente ' \
              '(despedida, bienvenida, mensaje de escalado o instrucciones). ' \
              'Solo funciona en la zona de pruebas. Úsala cuando el usuario pida ' \
              'establecer, por ejemplo, cómo debe despedirse el asistente.'

  param :campo, type: 'string',
                desc: 'Qué configurar: "despedida", "bienvenida", "mensaje_escalado" o "instrucciones".'
  param :valor, type: 'string',
                desc: 'El texto a guardar para ese campo.'

  def perform(tool_context, campo:, valor:)
    state = tool_context.state
    # Aislamiento: solo se permite aprovisionar desde el playground, nunca en
    # una conversación real (donde un cliente podría intentar manipular al bot).
    return solo_playground_msg unless state[:source].to_s == 'playground'

    key = ALLOWED_FIELDS[campo.to_s.strip.downcase]
    return campo_invalido_msg if key.nil?
    return 'El valor no puede estar vacío.' if valor.blank?

    @assistant.update!(config: @assistant.config.merge(key => valor))
    log_tool_usage('update_configuration', { assistant_id: @assistant.id, campo: key })
    "Listo. Guardé la #{campo} de este asistente: \"#{valor}\". Se aplicará solo a #{@assistant.name}."
  rescue ActiveRecord::RecordInvalid => e
    "No se pudo guardar: #{e.record.errors.full_messages.to_sentence}"
  end

  private

  def solo_playground_msg
    'Esta acción solo está disponible en la zona de pruebas del asistente, no en ' \
      'conversaciones reales.'
  end

  def campo_invalido_msg
    "No reconozco ese campo. Puedo configurar: #{ALLOWED_FIELDS.keys.join(', ')}."
  end
end
