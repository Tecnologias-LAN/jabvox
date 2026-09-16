# Compara una plantilla REAL aprobada en Meta contra lo que Jabvox generaría
# para esa misma plantilla, y muestra las diferencias campo por campo.
#
# Uso (en el servidor):
#   RAILS_ENV=production bundle exec rails runner \
#     scripts/diagnostics/diag_template_compare.rb ACCOUNT_ID NOMBRE_PLANTILLA
#
# Ejemplo:
#   ... diag_template_compare.rb 2 formulario_de_intencion
#
# Solo lee: no crea ni modifica nada en Meta. No imprime el access token.

require 'httparty'

account_id    = ARGV[0]
template_name = ARGV[1]

abort('Uso: rails runner scripts/diagnostics/diag_template_compare.rb ACCOUNT_ID NOMBRE_PLANTILLA') if account_id.blank? || template_name.blank?

account = Account.find(account_id)
inbox = account.inboxes.find { |i| i.channel.is_a?(Channel::Whatsapp) && i.channel.provider == 'whatsapp_cloud' }
abort('No encontré una bandeja de WhatsApp Cloud en esta cuenta.') if inbox.nil?

cfg     = inbox.channel.provider_config || {}
waba    = cfg['business_account_id']
token   = cfg['api_key']
version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
base    = "https://graph.facebook.com/#{version}"

puts '=' * 72
puts "Plantilla: #{template_name}   ·   WABA: #{waba}   ·   API: #{version}"
puts '=' * 72

# ── 1. Traer la plantilla real desde Meta ───────────────────────────────────
res = HTTParty.get(
  "#{base}/#{waba}/message_templates",
  headers: { 'Authorization' => "Bearer #{token}" },
  query: { name: template_name, fields: 'id,name,language,category,status,components,parameter_format' }
)

unless res.success?
  puts "No pude leer la plantilla desde Meta (HTTP #{res.code}):"
  puts res.body.to_s[0, 600]
  exit(1)
end

real = Array(res.parsed_response['data']).first
if real.nil?
  puts "Meta no devolvió ninguna plantilla llamada #{template_name.inspect} en este WABA."
  exit(1)
end

puts "\n########## 1. LO QUE META TIENE HOY (plantilla aprobada) ##########"
puts JSON.pretty_generate(real)

# ── 2. Reconstruir esa plantilla con el generador de Jabvox ─────────────────
# Se alimenta el generador con los mismos datos de la plantilla real, para ver
# si produce el mismo payload que Meta aceptó.
real_components = Array(real['components'])
body_c   = real_components.find { |c| c['type'].to_s.upcase == 'BODY' }
footer_c = real_components.find { |c| c['type'].to_s.upcase == 'FOOTER' }
header_c = real_components.find { |c| c['type'].to_s.upcase == 'HEADER' }
buttons_c = real_components.find { |c| c['type'].to_s.upcase == 'BUTTONS' }

jabvox_params = {
  name: real['name'],
  category: real['category'],
  language: real['language'],
  body: body_c&.dig('text'),
  footer: footer_c&.dig('text'),
  header_type: header_c&.dig('format'),
  header_content: header_c&.dig('text'),
  buttons: Array(buttons_c&.dig('buttons')).map do |b|
    {
      type: b['type'],
      text: b['text'],
      url: b['url'],
      phone_number: b['phone_number'],
      flow_id: b['flow_id'],
      navigate_screen: b['navigate_screen']
    }.compact
  end
}

manager = Jabvox::WhatsappTemplatesManager.new(account)
generated = manager.send(:build_components, jabvox_params)

puts "\n########## 2. LO QUE JABVOX ENVIARÍA PARA ESA MISMA PLANTILLA ##########"
puts JSON.pretty_generate(generated)

# ── 3. Diferencias ──────────────────────────────────────────────────────────
puts "\n########## 3. DIFERENCIAS ##########"

def normalize(value)
  case value
  when Hash  then value.to_h { |k, v| [k.to_s, normalize(v)] }.sort.to_h
  when Array then value.map { |v| normalize(v) }
  else value
  end
end

diffs = []
generated.each do |gen|
  type = gen[:type].to_s.upcase
  meta_side = real_components.find { |c| c['type'].to_s.upcase == type }
  if meta_side.nil?
    diffs << "· Jabvox envía un componente #{type} que la plantilla de Meta NO tiene."
    next
  end

  g = normalize(gen)
  m = normalize(meta_side)
  # Meta agrega campos informativos que no se mandan al crear; se comparan solo
  # las claves que Jabvox sí envía.
  g.each do |key, gen_value|
    next if key == 'type'

    meta_value = m[key]
    next if normalize(gen_value) == normalize(meta_value)

    diffs << "· #{type}.#{key}\n    Jabvox: #{gen_value.inspect}\n    Meta  : #{meta_value.inspect}"
  end
end

real_components.each do |meta_side|
  type = meta_side['type'].to_s.upcase
  next if generated.any? { |g| g[:type].to_s.upcase == type }

  diffs << "· La plantilla de Meta tiene un componente #{type} que Jabvox NO envía."
end

if diffs.empty?
  puts 'Sin diferencias: Jabvox reproduce exactamente la plantilla aprobada.'
else
  puts diffs.join("\n")
end

# ── 4. El Flow al que apunta el botón, si lo hay ────────────────────────────
flow_button = Array(buttons_c&.dig('buttons')).find { |b| b['type'].to_s.upcase == 'FLOW' }
if flow_button
  flow_id = flow_button['flow_id']
  puts "\n########## 4. FLOW ENLAZADO (#{flow_id}) ##########"
  flow_res = HTTParty.get(
    "#{base}/#{flow_id}",
    headers: { 'Authorization' => "Bearer #{token}" },
    query: { fields: 'id,name,status,categories,validation_errors,json_version' }
  )
  puts "HTTP #{flow_res.code}"
  puts flow_res.body.to_s[0, 800]

  puts "\n--- Flow JSON que Meta tiene guardado ---"
  assets = HTTParty.get(
    "#{base}/#{flow_id}/assets",
    headers: { 'Authorization' => "Bearer #{token}" }
  )
  puts "HTTP #{assets.code}"
  puts assets.body.to_s[0, 800]
end

puts "\n#{'=' * 72}"
puts 'FIN'
puts '=' * 72
