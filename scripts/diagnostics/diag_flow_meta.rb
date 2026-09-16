# Diagnóstico del ciclo de vida de un WhatsApp Flow contra Meta.
#
# Uso (en el servidor):
#   RAILS_ENV=production bundle exec rails runner scripts/diagnostics/diag_flow_meta.rb ACCOUNT_ID [INBOX_ID]
#
# Crea un Flow de prueba en tu WABA y prueba, uno por uno, los pasos que hoy
# fallan. NO imprime el access token en ningún momento. El Flow de prueba queda
# creado en Meta: bórralo desde WhatsApp Manager cuando termines (o con el
# comando DELETE que el propio script imprime al final).

require 'httparty'
require 'tempfile'
require 'shellwords'

account_id = ARGV[0]
inbox_id   = ARGV[1]

abort('Uso: rails runner scripts/diagnostics/diag_flow_meta.rb ACCOUNT_ID [INBOX_ID]') if account_id.blank?

account = Account.find(account_id)
inbox =
  if inbox_id.present?
    account.inboxes.find(inbox_id)
  else
    account.inboxes.find { |i| i.channel.is_a?(Channel::Whatsapp) && i.channel.provider == 'whatsapp_cloud' }
  end
abort('No encontré una bandeja de WhatsApp Cloud en esta cuenta.') if inbox.nil?

channel = inbox.channel
cfg     = channel.provider_config || {}
waba    = cfg['business_account_id']
token   = cfg['api_key']
version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
base    = "https://graph.facebook.com/#{version}"

puts '=' * 70
puts "Cuenta   : #{account.name} (##{account.id})"
puts "Bandeja  : #{inbox.name} (##{inbox.id})"
puts "WABA     : #{waba.inspect}"
puts "Versión  : #{version}"
puts "Token    : #{token.present? ? "presente (#{token.length} caracteres)" : 'AUSENTE'}"
puts '=' * 70

abort('Falta business_account_id o api_key en el canal.') if waba.blank? || token.blank?

def show(step, response)
  puts "\n--- #{step} ---"
  puts "HTTP #{response.code}"
  body = response.body.to_s
  puts(body.length > 900 ? "#{body[0, 900]}…" : body)
  response
end

name = "diag_flow_#{Time.now.to_i}"

# ── 1. Crear el Flow ────────────────────────────────────────────────────────
created = show('1) POST /{WABA}/flows (crear)', HTTParty.post(
                                                  "#{base}/#{waba}/flows",
                                                  headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' },
                                                  body: { name: name, categories: ['SURVEY'] }.to_json
                                                ))

flow_id = created.parsed_response.is_a?(Hash) ? created.parsed_response['id'] : nil
if flow_id.blank?
  puts "\nNo se pudo crear el Flow: los pasos siguientes se omiten."
  exit(1)
end
puts "\nFLOW_ID = #{flow_id}"

flow_json = {
  version: '7.3',
  screens: [
    {
      id: 'INICIO', title: 'Inicio', terminal: true,
      layout: {
        type: 'SingleColumnLayout',
        children: [
          { type: 'TextHeading', text: 'Prueba de diagnóstico' },
          { type: 'TextArea', name: 'comentario', label: 'Comentario' },
          { :type => 'Footer', :label => 'Enviar', 'on-click-action' => { name: 'complete' } }
        ]
      }
    }
  ]
}

# ── 2. Subir el Flow JSON: tres formas distintas ────────────────────────────
# Este es el paso que hoy responde "(#100) The parameter file is required".
# Probamos las variantes para ver cuál acepta Meta.

tempfile = Tempfile.new(['flow', '.json'])
tempfile.write(flow_json.to_json)
tempfile.rewind

puts "\n########## VARIANTE A: HTTParty multipart (lo que usa Jabvox hoy) ##########"
show('2A) POST /{FLOW_ID}/assets', HTTParty.post(
                                     "#{base}/#{flow_id}/assets",
                                     headers: { 'Authorization' => "Bearer #{token}" },
                                     multipart: true,
                                     body: { name: 'flow.json', asset_type: 'FLOW_JSON', file: File.open(tempfile.path, 'rb') }
                                   ))

puts "\n########## VARIANTE B: curl (multipart correcto del sistema) ##########"
cmd = [
  'curl', '-s', '-X', 'POST', "#{base}/#{flow_id}/assets",
  '-H', "Authorization: Bearer #{token}",
  '-F', 'name=flow.json',
  '-F', 'asset_type=FLOW_JSON',
  '-F', "file=@#{tempfile.path};type=application/json"
]
puts `#{cmd.map { |c| Shellwords.escape(c) }.join(' ')}`

puts "\n########## VARIANTE C: multipart armado a mano con Net::HTTP ##########"
require 'net/http'
uri = URI("#{base}/#{flow_id}/assets")
boundary = "----JabvoxDiag#{SecureRandom.hex(8)}"
payload = +''
{ 'name' => 'flow.json', 'asset_type' => 'FLOW_JSON' }.each do |k, v|
  payload << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{k}\"\r\n\r\n#{v}\r\n"
end
payload << "--#{boundary}\r\n"
payload << "Content-Disposition: form-data; name=\"file\"; filename=\"flow.json\"\r\n"
payload << "Content-Type: application/json\r\n\r\n"
payload << "#{flow_json.to_json}\r\n"
payload << "--#{boundary}--\r\n"

req = Net::HTTP::Post.new(uri)
req['Authorization'] = "Bearer #{token}"
req['Content-Type']  = "multipart/form-data; boundary=#{boundary}"
req.body = payload
res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
puts "HTTP #{res.code}"
puts res.body.to_s[0, 900]

# ── 3. Estado y publicación ─────────────────────────────────────────────────
show('3) GET /{FLOW_ID} (estado y errores de validación)', HTTParty.get(
                                                             "#{base}/#{flow_id}",
                                                             headers: { 'Authorization' => "Bearer #{token}" },
                                                             query: { fields: 'id,name,status,categories,validation_errors' }
                                                           ))

show('4) POST /{FLOW_ID}/publish', HTTParty.post(
                                     "#{base}/#{flow_id}/publish",
                                     headers: { 'Authorization' => "Bearer #{token}" }
                                   ))

tempfile.close
tempfile.unlink

puts "\n#{'=' * 70}"
puts 'LISTO. Para borrar el Flow de prueba (solo funciona si quedó en DRAFT):'
puts %(  curl -s -X DELETE "#{base}/#{flow_id}" -H "Authorization: Bearer $TOKEN")
puts "Flow de prueba: #{name} (#{flow_id})"
puts '=' * 70
