# Validación de las tres URLs de la configuración global de Automations.
#
# Equivalente Ruby de `assertSafeBaseUrl` / los `IsUrl` del DTO de la plataforma
# Automations: exige URLs ABSOLUTAS y con esquema http/https.
#
# POR QUÉ SE VALIDA AQUÍ Y NO SOLO EN EL OTRO LADO: la "Frontend URL" termina en
# el `src` de un iframe del panel, así que un `javascript:` guardado aquí es XSS
# ejecutándose en Jabvox, no simplemente una URL que no funciona. El 400 que
# devolvería la plataforma remota llega DEMASIADO TARDE, porque para entonces el
# valor ya estaría persistido y el iframe ya lo habría usado. Por eso se rechaza
# en el momento de guardar.
#
# `require_tld` NO se exige, igual que en el otro repo: `http://localhost:3001` y
# `http://172.17.0.1:3001` son configuraciones normales de despliegue, y con TLD
# obligatorio un despliegue local no podría aprobarse nunca.
module Automations::UrlValidator
  MAX_URL_LENGTH = 2048

  # Etiquetas humanas de las tres URLs. Son los nombres EXACTOS de los campos de
  # la pantalla del super admin, para que el error apunte al campo a corregir.
  LABELS = {
    serviceUrl: 'Service URL',
    frontendUrl: 'Frontend URL (iframe)',
    jabvoxCallbackUrl: 'Jabvox Callback URL'
  }.freeze

  # Primer problema encontrado en el hash de las tres URLs, o nil si están bien.
  def self.validation_error(urls)
    LABELS.each do |key, label|
      error = url_error(urls[key], label)
      return error if error
    end
    nil
  end

  # Valida UNA url: nil si es correcta, un mensaje accionable si no.
  def self.url_error(value, label)
    url = value.to_s.strip
    return "Falta \"#{label}\": es obligatoria para la prueba de conexión." if url.blank?
    return "\"#{label}\" es demasiado larga (máximo #{MAX_URL_LENGTH} caracteres)." if url.length > MAX_URL_LENGTH

    return nil if http_url?(url)

    "\"#{label}\" debe ser una URL absoluta http(s) e incluir el host, " \
      'p.ej. https://automatizaciones.midominio.com'
  end

  # ¿Es una URL absoluta http/https con host?
  #
  # La comprobación que importa es la CLASE resultante, no que el parseo tenga
  # éxito: `URI.parse('javascript:alert(1)')` no lanza nada, devuelve un
  # `URI::Generic`. Solo `URI::HTTP` (y `URI::HTTPS`, que hereda de ella) pasa,
  # con lo que quedan fuera `javascript:`, `data:`, `ftp://`, los relativos
  # (`//host`) y los que no llevan esquema. El `host.present?` descarta además
  # `http://` a secas, que sí parsea como `URI::HTTP` pero con host vacío.
  def self.http_url?(url)
    parsed = begin
      URI.parse(url)
    rescue URI::Error
      nil
    end

    parsed.is_a?(URI::HTTP) && parsed.host.present?
  end
end
