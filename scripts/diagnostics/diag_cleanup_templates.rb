# Borra de Meta (y de Jabvox) las plantillas de prueba creadas por los scripts
# de diagnóstico.
#
# Uso (en el servidor):
#   RAILS_ENV=production bundle exec rails runner \
#     scripts/diagnostics/diag_cleanup_templates.rb ACCOUNT_ID [PREFIJO] [--force]
#
#   ... diag_cleanup_templates.rb 2                  # lista lo que borraría (no borra)
#   ... diag_cleanup_templates.rb 2 diag_ --force    # borra las que empiezan por diag_
#   ... diag_cleanup_templates.rb 2 prueba --force   # borra las que empiezan por prueba
#
# Sin --force solo muestra la lista, para poder revisarla antes. El prefijo por
# defecto es "diag_", de modo que nunca toca plantillas de producción salvo que
# se pida otro explícitamente. No imprime el access token.

require 'httparty'

account_id = ARGV[0]
prefix     = (ARGV[1] if ARGV[1].present? && !ARGV[1].start_with?('--')) || 'diag_'
force      = ARGV.include?('--force')

abort('Uso: rails runner scripts/diagnostics/diag_cleanup_templates.rb ACCOUNT_ID [PREFIJO] [--force]') if account_id.blank?
abort('El prefijo no puede quedar vacío: borraría TODAS las plantillas.') if prefix.blank?

account = Account.find(account_id)
inbox = account.inboxes.find { |i| i.channel.is_a?(Channel::Whatsapp) && i.channel.provider == 'whatsapp_cloud' }
abort('No encontré una bandeja de WhatsApp Cloud en esta cuenta.') if inbox.nil?

cfg     = inbox.channel.provider_config || {}
waba    = cfg['business_account_id']
token   = cfg['api_key']
version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
base    = "https://graph.facebook.com/#{version}"

puts '=' * 72
puts "Cuenta: #{account.name} (##{account.id})  ·  WABA: #{waba}"
puts "Prefijo: #{prefix.inspect}   ·   Modo: #{force ? 'BORRAR' : 'solo listar'}"
puts '=' * 72

# Todas las plantillas del WABA (paginando).
def fetch_all(base, waba, token, url = nil)
  response =
    if url
      HTTParty.get(url, headers: { 'Authorization' => "Bearer #{token}" })
    else
      HTTParty.get("#{base}/#{waba}/message_templates",
                   headers: { 'Authorization' => "Bearer #{token}" },
                   query: { fields: 'id,name,status', limit: 200 })
    end
  return [] unless response.success?

  data = response.parsed_response['data'] || []
  nxt = response.parsed_response.dig('paging', 'next')
  nxt.present? ? data + fetch_all(base, waba, token, nxt) : data
end

todas = fetch_all(base, waba, token)
objetivo = todas.select { |t| t['name'].to_s.start_with?(prefix) }

if objetivo.empty?
  puts "\nNo hay plantillas que empiecen por #{prefix.inspect} en este WABA."
  exit(0)
end

puts "\nPlantillas encontradas (#{objetivo.size}):"
objetivo.each { |t| puts "  · #{t['name']}  (#{t['status']})" }

unless force
  puts "\nNo se borró nada. Vuelve a ejecutarlo con --force para eliminarlas:"
  puts "  rails runner scripts/diagnostics/diag_cleanup_templates.rb #{account_id} #{prefix} --force"
  exit(0)
end

puts "\nBorrando…"
borradas = 0
fallidas = []

objetivo.each do |tpl|
  # Meta admite borrar por nombre sobre el WABA o por id de la plantilla; según
  # los permisos del token una funciona y la otra no, así que se intentan ambas.
  response = HTTParty.delete(
    "#{base}/#{waba}/message_templates",
    headers: { 'Authorization' => "Bearer #{token}" },
    query: { name: tpl['name'] }
  )

  unless response.success?
    response = HTTParty.delete(
      "#{base}/#{tpl['id']}",
      headers: { 'Authorization' => "Bearer #{token}" }
    )
  end

  if response.success?
    borradas += 1
    puts "  ✅ #{tpl['name']}"
    # Quitar también la copia local para que no reaparezca en el listado.
    account.jabvox_whatsapp_templates.where(name: tpl['name']).destroy_all
  else
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response.dig('error', 'message') : response.body
    fallidas << "#{tpl['name']}: #{error}"
    puts "  ❌ #{tpl['name']} — #{error}"
  end
end

puts "\n#{'=' * 72}"
puts "Borradas: #{borradas} de #{objetivo.size}"
if fallidas.any?
  puts "Fallidas:\n  #{fallidas.join("\n  ")}"
  if fallidas.any? { |f| f.include?('Need permission') }
    puts "\nEl token puede crear y leer plantillas pero no borrarlas. Opciones:"
    puts '  · Bórralas desde WhatsApp Manager → Herramientas de la cuenta → Plantillas.'
    puts '  · O usa un token de usuario del sistema con el permiso'
    puts '    whatsapp_business_management sobre este WABA.'
  end
end
puts '=' * 72
