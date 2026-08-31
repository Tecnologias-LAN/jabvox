# frozen_string_literal: true

# jabvox.label.find_by_age — conversaciones que llevan AL MENOS `minHours` con
# una etiqueta puesta.
#
# DE DÓNDE SALE LA FECHA: `jabvox_conversation_label_logs`, que guarda los
# intervalos applied_at/removed_at de cada etiqueta. La API estándar no expone
# cuándo se aplicó una etiqueta, así que sin este registro no habría forma de
# construir una cadena de seguimiento por tiempo.
class Jabvox::Flows::Nodes::Jabvox::LabelFindByAgeNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.label.find_by_age'
  label 'Conversaciones por antigüedad de etiqueta'
  items_path 'conversations'

  DEFAULT_MIN_HOURS = 24
  DEFAULT_LIMIT = 200
  MAX_LIMIT = 500

  def perform
    config = read_config
    now = Time.current
    logs = open_logs(config)
    aged = logs.select { |log| hours_applied(log, now) >= config[:min_hours] }

    rows, without_phone = collect(aged, config, now)
    tally = { checked: aged.length, without_phone: without_phone, total_logs: logs.length }
    build_output(config, rows, tally, now)
  end

  private

  def read_config
    label = param(:label).to_s.strip
    fail_with!('Falta la "Etiqueta": elige la etiqueta de conversación cuya antigüedad quieres medir.') if
      label.blank?

    # Vacío = 24 h, NO 0 h: con `to_i` valía 0 y el nodo devolvía conversaciones
    # etiquetadas hace un segundo, saltándose la espera entera.
    min_hours = number_or(param(:minHours), DEFAULT_MIN_HOURS)
    fail_with!(bad_hours_message) if !min_hours.finite? || min_hours.negative?

    { label: label.downcase, min_hours: min_hours,
      limit: int_or(param(:limit), DEFAULT_LIMIT, min: 1, max: MAX_LIMIT),
      only_without_reply: opt_out?(param(:onlyWithoutReply)),
      # OPT-IN: los flujos guardados antes de este param no traen la clave.
      only_with_phone: opt_in?(param(:onlyWithPhone)),
      statuses: str_list(param(:statuses)).map(&:downcase) }
  end

  def bad_hours_message
    'Las "Horas mínimas con la etiqueta" deben ser un número de horas >= 0 ' \
      "(llegó «#{param(:minHours)}»)."
  end

  # Intervalos ABIERTOS (la etiqueta sigue puesta) de esta cuenta.
  def open_logs(config)
    JabvoxConversationLabelLog.where(account_id: account.id)
                              .for_label(config[:label]).open
                              .order(applied_at_jabvox: :asc)
                              .limit(config[:limit]).to_a
  end

  def hours_applied(log, now)
    ((now - log.applied_at_jabvox) / 3600.0).round(2)
  end

  def collect(aged, config, now)
    conversations = account.conversations.where(id: aged.map(&:conversation_id))
                           .includes(:contact).index_by(&:id)
    without_phone = 0
    rows = aged.filter_map do |log|
      conversation = conversations[log.conversation_id]
      # Sin conversación viva no se puede releer ni etiquetar: el log quedó
      # huérfano. Se descarta en vez de romper el flujo.
      next if conversation.nil?
      next unless status_matches?(conversation, config)

      has_phone = conversation.contact&.phone_number.present?
      without_phone += 1 unless has_phone
      build_row(log, conversation, config, has_phone, now)
    end
    [rows.compact, without_phone]
  end

  def status_matches?(conversation, config)
    config[:statuses].empty? || config[:statuses].include?(conversation.status.to_s.downcase)
  end

  def build_row(log, conversation, config, has_phone, now)
    last_inbound = last_inbound_epoch(conversation)
    applied_epoch = log.applied_at_jabvox.to_i
    # Respondió si su último mensaje ENTRANTE es posterior a la etiqueta: es lo
    # que rompe la cadena de seguimiento cuando el cliente contesta.
    replied = last_inbound.present? && last_inbound > applied_epoch
    return nil if config[:only_without_reply] && replied
    return nil if config[:only_with_phone] && !has_phone

    row(log, conversation, now,
        applied_epoch: applied_epoch, last_inbound: last_inbound, replied: replied, has_phone: has_phone)
  end

  def row(log, conversation, now, **state)
    { 'conversation_id' => conversation.id, 'display_id' => conversation.display_id,
      'label' => log.label_jabvox, 'applied_at' => log.applied_at_jabvox.iso8601,
      'applied_at_epoch' => state[:applied_epoch], 'hours_applied' => hours_applied(log, now),
      'status' => conversation.status.to_s, 'labels' => conversation.label_list.to_a.map(&:to_s),
      'contact' => contact_view(conversation.contact), 'contact_id' => conversation.contact_id,
      # Se publica en la fila para poder ramificar DENTRO del bucle sin activar
      # el filtro.
      'has_phone' => state[:has_phone], 'last_inbound_at_epoch' => state[:last_inbound],
      'replied_since_label' => state[:replied] }
  end

  # Epoch del último mensaje ENTRANTE de la conversación, o nil si no consta.
  def last_inbound_epoch(conversation)
    conversation.messages.where(message_type: :incoming).maximum(:created_at)&.to_i
  end

  def build_output(config, rows, tally, now)
    # ¿Vino cortada la lista? Con tantas filas como el tope hay conversaciones
    # sin mirar, y quedarse callado hacía parecer que el flujo había terminado.
    truncated = tally[:total_logs] >= config[:limit]
    base = output_base(config, rows, tally, truncated, now)
    truncated ? base.merge('aviso' => truncated_warning(config)) : base
  end

  def output_base(config, rows, tally, truncated, now)
    { 'label' => config[:label], 'minHours' => config[:min_hours],
      'onlyWithoutReply' => config[:only_without_reply], 'onlyWithPhone' => config[:only_with_phone],
      'count' => rows.length,
      # Cuántas traía el registro con la antigüedad pedida, ANTES de descartar
      # por estado o por haber respondido: sin esto un 0 no se sabe explicar.
      'checked' => tally[:checked], 'without_phone' => tally[:without_phone],
      'truncated' => truncated, 'limit' => config[:limit],
      'now' => now.iso8601, 'conversations' => rows }
  end

  def truncated_warning(config)
    "Se alcanzó el tope de #{config[:limit]} conversaciones por consulta. Las que no entraron NO se " \
      'han procesado en esta vuelta: se tomarán en las siguientes, o sube el "Límite" (máx. 500).'
  end
end
