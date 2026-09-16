# Crea en Meta una plantilla de CADA tipo soportado, usando el mismo generador
# que usa Jabvox desde la interfaz, y reporta cuáles acepta y cuáles rechaza.
#
# Uso (en el servidor):
#   RAILS_ENV=production bundle exec rails runner \
#     scripts/diagnostics/diag_all_template_types.rb ACCOUNT_ID [SOLO_TIPO]
#
#   ... diag_all_template_types.rb 2              # todos los tipos
#   ... diag_all_template_types.rb 2 carousel     # solo uno
#
# Crea plantillas REALES en tu WABA (prefijo diag_). Meta no permite borrarlas
# por API, así que quedan en WhatsApp Manager para que las elimines a mano.
# No imprime el access token.

account_id = ARGV[0]
only_kind  = ARGV[1]

abort('Uso: rails runner scripts/diagnostics/diag_all_template_types.rb ACCOUNT_ID [TIPO]') if account_id.blank?

account = Account.find(account_id)
inbox = account.inboxes.find { |i| i.channel.is_a?(Channel::Whatsapp) && i.channel.provider == 'whatsapp_cloud' }
abort('No encontré una bandeja de WhatsApp Cloud en esta cuenta.') if inbox.nil?

stamp   = Time.now.to_i
manager = Jabvox::WhatsappTemplatesManager.new(account)

puts '=' * 72
puts "Cuenta: #{account.name} (##{account.id})  ·  Bandeja: #{inbox.name} (##{inbox.id})"
puts '=' * 72

# Un Flow publicado de la cuenta, para la plantilla con botón de formulario.
published_flow = account.jabvox_whatsapp_flows.where(status: 'published').where.not(meta_flow_id: nil).last

casos = {
  'texto' => {
    name: "diag_texto_#{stamp}", category: 'UTILITY', language: 'es',
    body: 'Hola {{nombre}}, tu pedido {{pedido}} ya fue despachado.',
    footer: 'Gracias por comprar con nosotros',
    var_descriptions: { 'nombre' => 'Ana', 'pedido' => 'A-1234' }
  },
  'texto_posicional' => {
    name: "diag_posicional_#{stamp}", category: 'UTILITY', language: 'es',
    body: 'Hola {{1}}, tu cita quedó para el {{2}}.',
    var_descriptions: { '1' => 'Ana', '2' => '5 de mayo' }
  },
  'botones' => {
    name: "diag_botones_#{stamp}", category: 'UTILITY', language: 'es',
    body: 'Hola {{nombre}}, ¿confirmas tu cita?',
    var_descriptions: { 'nombre' => 'Ana' },
    buttons: [
      { type: 'QUICK_REPLY', text: 'Confirmar' },
      { type: 'QUICK_REPLY', text: 'Cancelar' }
    ]
  },
  'url_y_telefono' => {
    name: "diag_url_tel_#{stamp}", category: 'MARKETING', language: 'es',
    body: 'Hola {{nombre}}, mira nuestras ofertas de hoy.',
    var_descriptions: { 'nombre' => 'Ana' },
    buttons: [
      { type: 'URL', text: 'Ver ofertas', url: 'https://jabvox.co/ofertas' },
      { type: 'PHONE_NUMBER', text: 'Llamar', phone_number: '+573054463029' }
    ]
  },
  'copy_code' => {
    name: "diag_cupon_#{stamp}", category: 'MARKETING', language: 'es',
    body: 'Hola {{nombre}}, tenemos un cupón para ti.',
    var_descriptions: { 'nombre' => 'Ana' },
    buttons: [{ type: 'COPY_CODE', text: 'Copiar cupón', example: 'VERANO25' }]
  },
  'location' => {
    name: "diag_location_#{stamp}", category: 'UTILITY', language: 'es',
    header_type: 'LOCATION',
    body: 'Hola {{nombre}}, tu pedido sale desde esta sede.',
    var_descriptions: { 'nombre' => 'Ana' }
  },
  'lto' => {
    name: "diag_lto_#{stamp}", category: 'MARKETING', language: 'es',
    body: 'Hola {{nombre}}, oferta por tiempo limitado.',
    var_descriptions: { 'nombre' => 'Ana' },
    limited_time_offer: true,
    buttons: [{ type: 'COPY_CODE', text: 'Copiar cupón', example: 'FLASH50' }]
  },
  'authentication' => {
    name: "diag_auth_#{stamp}", category: 'AUTHENTICATION', language: 'es',
    template_kind: 'authentication',
    auth_config: { add_security_recommendation: true, code_expiration_minutes: 10, otp_type: 'COPY_CODE' }
  },
  'flow' => {
    name: "diag_flow_tpl_#{stamp}", category: 'MARKETING', language: 'es',
    body: 'Hola {{nombre}}, cuéntanos tu experiencia.',
    var_descriptions: { 'nombre' => 'Ana' },
    buttons: [{ type: 'FLOW', text: 'Responder', flow_id: published_flow&.meta_flow_id }]
  }
}

# El carrusel necesita media subida (asset handle), que exige WHATSAPP_APP_ID.
# Se intenta solo si hay uno configurado.
app_id = GlobalConfigService.load('WHATSAPP_APP_ID', '').presence ||
         InstallationConfig.find_by(name: 'WHATSAPP_APP_ID')&.value.presence

resultados = {}

casos.each do |kind, params|
  next if only_kind.present? && only_kind != kind

  puts "\n#{'─' * 72}"
  puts "TIPO: #{kind}"
  puts '─' * 72

  if kind == 'flow' && published_flow.blank?
    puts 'OMITIDO: no hay ningún Flow publicado en esta cuenta para enlazar.'
    resultados[kind] = 'omitido (sin Flow publicado)'
    next
  end

  # Muestra el payload exacto que se manda a Meta.
  begin
    components = manager.send(:build_components, params)
    puts 'Componentes que se envían:'
    puts JSON.pretty_generate(components)
  rescue StandardError => e
    puts "ERROR armando el payload: #{e.class}: #{e.message}"
    resultados[kind] = "error local: #{e.message}"
    next
  end

  result = manager.create(inbox, params)
  if result[:success]
    tpl = result[:template]
    puts "\n✅ META LA ACEPTÓ  ·  id=#{tpl.meta_template_id}  estado=#{tpl.status}"
    resultados[kind] = "OK (#{tpl.status})"
  else
    puts "\n❌ RECHAZADA: #{result[:error]}"
    resultados[kind] = "FALLÓ: #{result[:error]}"
  end
end

unless only_kind.present? && only_kind != 'carousel'
  puts "\n#{'─' * 72}"
  puts 'TIPO: carousel'
  puts '─' * 72
  if app_id.blank?
    puts 'OMITIDO: falta WHATSAPP_APP_ID, necesario para subir la imagen de cada tarjeta.'
    resultados['carousel'] = 'omitido (falta WHATSAPP_APP_ID)'
  else
    puts "Hay WHATSAPP_APP_ID configurado (#{app_id.length} caracteres)."
    puts 'Este tipo exige subir una imagen por tarjeta; pruébalo desde la interfaz.'
    resultados['carousel'] = 'requiere subir media: probar desde la interfaz'
  end
end

puts "\n#{'=' * 72}"
puts 'RESUMEN'
puts '=' * 72
resultados.each { |kind, estado| puts format('%<kind>-18s %<estado>s', kind: kind, estado: estado) }
puts "\nLas plantillas creadas empiezan por 'diag_' y quedan en tu WABA."
puts 'Bórralas desde WhatsApp Manager cuando termines.'
puts '=' * 72
