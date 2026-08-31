# frozen_string_literal: true

# Identidad de los elementos de un bucle y texto del informe final. El resumen
# daba CONTEOS pero no decía A QUIÉN; sin esto un informe no puede nombrar a nadie.
module Jabvox::Flows::Engine::LoopReport
  # Tope de nombres listados por sección: con 200 elementos el texto explota.
  MAX_NAMES = 20

  NAME_PATHS = ['contact.name', 'meta.sender.name', 'name', 'contact_name'].freeze
  PHONE_PATHS = ['contact.phone_number', 'meta.sender.phone_number', 'phone_number'].freeze
  EMAIL_PATHS = ['contact.email', 'meta.sender.email', 'email'].freeze
  CONTACT_ID_PATHS = ['contact.id', 'meta.sender.id', 'contact_id'].freeze
  LEAD_ID_PATHS = ['lead_number', 'lead.id', 'lead_id'].freeze
  CONVERSATION_PATHS = ['conversation_display_id', 'display_id', 'conversation.id'].freeze

  module_function

  # Primer valor no vacío de una lista de rutas con puntos.
  def pick(root, paths)
    paths.each do |path|
      value = path.split('.').reduce(root) { |cur, seg| cur.is_a?(Hash) ? cur[seg] : nil }
      return value unless value.nil? || value == ''
    end
    nil
  end

  # Escalar legible, o nil si no lo es.
  def scalar(value)
    return value if value.is_a?(Numeric)
    return value.strip if value.is_a?(String) && value.strip != ''

    nil
  end

  # Deduce a QUIÉN corresponde un elemento: cubre lead, conversación y contacto.
  def identify(item)
    return { etiqueta: scalar(item)&.to_s || 'elemento sin datos' } unless item.is_a?(Hash)

    parts = {
      nombre: scalar(pick(item, NAME_PATHS)), telefono: scalar(pick(item, PHONE_PATHS)),
      email: scalar(pick(item, EMAIL_PATHS)), contacto_id: scalar(pick(item, CONTACT_ID_PATHS)),
      lead_id: scalar(pick(item, LEAD_ID_PATHS)), conversacion_id: scalar(pick(item, CONVERSATION_PATHS))
    }
    build_identity(parts)
  end

  def build_identity(parts)
    identity = { etiqueta: label_for(parts) }
    identity[:contactoId] = parts[:contacto_id] unless parts[:contacto_id].nil?
    identity[:leadId] = parts[:lead_id] unless parts[:lead_id].nil?
    identity[:conversacionId] = parts[:conversacion_id] unless parts[:conversacion_id].nil?
    identity[:telefono] = parts[:telefono].to_s unless parts[:telefono].nil?
    identity[:email] = parts[:email].to_s unless parts[:email].nil?
    identity
  end

  # Orden de preferencia: lo que un humano reconoce antes.
  def label_for(parts)
    base = base_label_for(parts)
    ref = reference_for(parts)
    return "#{base} (#{ref})" if base && ref

    (base || ref || 'elemento sin identificar').to_s
  end

  def base_label_for(parts)
    directo = parts[:nombre] || parts[:telefono] || parts[:email]
    return directo if directo
    return "contacto #{parts[:contacto_id]}" if parts[:contacto_id]

    nil
  end

  def reference_for(parts)
    return "conv. ##{parts[:conversacion_id]}" unless parts[:conversacion_id].nil?
    return "lead ##{parts[:lead_id]}" unless parts[:lead_id].nil?

    nil
  end

  # Une nombres recortando a `max` y diciendo cuántos quedan fuera.
  def join_names(names, max = MAX_NAMES)
    return '—' if names.empty?
    return names.join(', ') if names.length <= max

    "#{names.first(max).join(', ')} y #{names.length - max} más"
  end

  # Texto del informe, listo para el cuerpo de una tarea o un correo. El motor de
  # plantillas no tiene bucles, así que se compone aquí y el flujo lo referencia
  # con UN solo {{...}}.
  def build_text(procesados:, con_error:, total:, correctos:, fallidos:)
    return 'No había elementos que procesar: no se hizo nada.' if total.zero?

    lines = ["Procesados con éxito: #{procesados} de #{total}.", "Con error: #{con_error}.",
             '', "Correctos: #{join_names(correctos)}"]
    lines.concat(failure_lines(fallidos)) if con_error.positive?
    lines.join("\n")
  end

  def failure_lines(fallidos)
    shown = fallidos.first(MAX_NAMES).map { |f| "- #{f[:etiqueta]}: #{f[:error]}" }
    rest = fallidos.length - shown.length
    lines = ['', 'Fallidos:', *shown]
    lines << "- y #{rest} más" if rest.positive?
    lines
  end
end
