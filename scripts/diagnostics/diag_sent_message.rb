# Inspecciona los últimos mensajes de plantilla enviados en una cuenta: qué
# parámetros se guardaron, qué estado devolvió Meta y, si la plantilla tenía un
# formulario, si llegó la respuesta.
#
# Uso (en el servidor):
#   RAILS_ENV=production bundle exec rails runner \
#     scripts/diagnostics/diag_sent_message.rb ACCOUNT_ID [CUANTOS]
#
# Solo lee: no envía ni modifica nada. No imprime credenciales.

account_id = ARGV[0]
limit      = (ARGV[1] || 5).to_i

abort('Uso: rails runner scripts/diagnostics/diag_sent_message.rb ACCOUNT_ID [CUANTOS]') if account_id.blank?

account = Account.find(account_id)

mensajes = account.messages
                  .where(message_type: [:outgoing, :template])
                  .where.not(additional_attributes: nil)
                  .order(created_at: :desc)
                  .limit(60)
                  .select { |m| m.additional_attributes.dig('template_params', 'name').present? }
                  .first(limit)

if mensajes.empty?
  puts 'No encontré mensajes de plantilla recientes en esta cuenta.'
  exit(0)
end

puts '=' * 72
puts "Cuenta: #{account.name} (##{account.id})  ·  últimos #{mensajes.size} envíos de plantilla"
puts '=' * 72

mensajes.each do |m| # rubocop:disable Metrics/BlockLength
  tp = m.additional_attributes['template_params'] || {}
  puts "\n#{'─' * 72}"
  puts "Mensaje ##{m.id}  ·  #{m.created_at}  ·  conversación #{m.conversation_id}"
  puts "Plantilla : #{tp['name']}  (#{tp['language']}, #{tp['category']})"
  puts "Estado    : #{m.status}"
  puts "source_id : #{m.source_id.inspect}"
  puts "Error     : #{m.external_error.inspect}" if m.external_error.present?

  puts "\nParámetros que se enviaron (processed_params):"
  puts JSON.pretty_generate(tp['processed_params'] || {})

  # Estado real reportado por Meta para ese envío.
  eventos = MessageStatusEvent.where(message_id: m.id).order(:occurred_at)
  if eventos.any?
    puts "\nEstados reportados por Meta:"
    eventos.each do |e|
      extra = [e.error_code, e.error_title].compact.join(' ')
      pricing = [e.pricing_category, (e.pricing_billable.nil? ? nil : "facturable=#{e.pricing_billable}")].compact.join(' ')
      puts "  · #{e.status.ljust(10)} #{e.occurred_at}  #{pricing} #{extra}".rstrip
    end
  else
    puts "\nSin eventos de estado de Meta para este mensaje."
  end

  # Si la plantilla llevaba formulario, ¿llegó la respuesta?
  flow_button = Array(tp.dig('processed_params', 'buttons')).find { |b| b.is_a?(Hash) && b['type'] == 'flow' }
  next if flow_button.blank?

  token = flow_button['flow_token']
  puts "\nFormulario: flow_token=#{token.inspect}"

  respuesta = account.messages
                     .where(conversation_id: m.conversation_id, message_type: :incoming)
                     .where('created_at >= ?', m.created_at)
                     .find { |r| r.content_attributes['whatsapp_flow_response'].present? }

  if respuesta
    puts '  ✅ Llegó la respuesta del formulario:'
    puts JSON.pretty_generate(respuesta.content_attributes['whatsapp_flow_response'])
    submission = JabvoxWhatsappFlowSubmission.find_by(account_id: account.id, flow_token: token)
    if submission
      puts "  Guardada como submission ##{submission.id} con #{submission.answers.count} respuesta(s)."
    else
      puts '  ⚠️  No se guardó como submission estructurada (solo quedó el jsonb del mensaje).'
    end
  else
    puts '  ⏳ Todavía no llegó ninguna respuesta de formulario en esa conversación.'
  end
end

puts "\n#{'=' * 72}"
puts 'FIN'
puts '=' * 72
