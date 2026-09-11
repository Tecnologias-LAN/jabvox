# Convierte la URL de EJEMPLO del media de una plantilla aprobada (la que Meta guarda en
# scontent.whatsapp.net / lookaside.fbsbx.com) en un media_id de WhatsApp usable en el envío.
#
# ¿Por qué? Una plantilla con header IMAGE/VIDEO/DOCUMENT EXIGE el componente header al
# enviar, con una imagen que Meta pueda resolver. La URL de scontent NO sirve como
# `image.link` (Meta la pide por HTTP/2 y recibe 403 -> "#100 Invalid parameter"). En
# cambio, sí es descargable por HTTP/1.1. Así que:
#   1) descargamos la imagen de scontent (HTTP/1.1),
#   2) la subimos a la Media API de Meta (/{phone_number_id}/media) -> media_id,
#   3) el envío usa header con { id: media_id }.
#
# Funciona para plantillas creadas en Jabvox Y en Meta (ambas exponen el ejemplo en
# example.header_handle). El media_id se cachea en la plantilla local (dura ~30 días en
# Meta) para no re-descargar/re-subir en cada envío del batch.
class Whatsapp::TemplateMediaResolverService
  GRAPH_VERSION = 'v20.0'.freeze
  META_MEDIA_HOSTS = %w[whatsapp.net fbsbx.com].freeze
  MEDIA_ID_TTL = 25.days # < 30 días que Meta conserva el media; margen de seguridad.

  pattr_initialize [:channel!, :media_url!, :media_type!, :template_name]

  # Devuelve un media_id de WhatsApp, o nil si no se pudo resolver (el llamador
  # entonces cae al comportamiento anterior de usar `link`).
  def call
    return nil if media_url.blank? || media_type.blank?
    return nil unless meta_hosted_url?(media_url)

    cached = cached_media_id
    return cached if cached.present?

    media_id = download_and_upload
    cache_media_id(media_id) if media_id.present?
    media_id
  rescue StandardError => e
    Rails.logger.error "[WA TemplateMedia] resolve failed for #{template_name}: #{e.class} #{e.message}"
    nil
  end

  private

  # Solo re-subimos URLs alojadas por Meta (scontent/lookaside). Una URL pública propia
  # se deja pasar como link (retornamos nil aquí para que el llamador use `link`).
  def meta_hosted_url?(url)
    host = URI.parse(url).host.to_s.downcase
    META_MEDIA_HOSTS.any? { |h| host.end_with?(h) } || host.include?('scontent')
  rescue URI::InvalidURIError
    false
  end

  def download_and_upload
    file, content_type = download_media
    return nil if file.blank?

    upload_to_meta(file, content_type)
  end

  # Descarga con Net::HTTP (HTTP/1.1). Con HTTP/2 Meta responde 403 a estas URLs.
  def download_media
    uri = URI.parse(media_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 10
    http.read_timeout = 30
    res = http.get(uri.request_uri, 'User-Agent' => 'Jabvox')
    return [nil, nil] unless res.is_a?(Net::HTTPSuccess)

    [res.body, res['content-type'].presence || default_content_type]
  end

  # POST multipart a /{phone_number_id}/media -> { "id": "..." }
  def upload_to_meta(binary, content_type)
    boundary = "----jabvox#{SecureRandom.hex(12)}"
    body = multipart_body(boundary, binary, content_type)

    uri = URI.parse("#{graph_base}/#{GRAPH_VERSION}/#{phone_number_id}/media")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 60
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{api_key}"
    req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    req.body = body

    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn "[WA TemplateMedia] /media upload #{res.code}: #{res.body}"
      return nil
    end

    JSON.parse(res.body)['id'].presence
  end

  def multipart_body(boundary, binary, content_type)
    filename = "template_header.#{extension_for(content_type)}"
    body = +''
    body << part(boundary, 'messaging_product', 'whatsapp')
    body << part(boundary, 'type', content_type)
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
    body << "Content-Type: #{content_type}\r\n\r\n"
    body << binary.dup.force_encoding('BINARY')
    body << "\r\n--#{boundary}--\r\n"
    body.force_encoding('BINARY')
  end

  def part(boundary, name, value)
    "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
  end

  # ── Caché del media_id en la plantilla local (meta_json) ──────────────────
  def template_record
    return @template_record if defined?(@template_record)

    @template_record = channel.inbox&.account&.jabvox_whatsapp_templates
                              &.find_by(name: template_name, inbox_id: channel.inbox&.id)
  end

  def cached_media_id
    rec = template_record
    return nil if rec.blank?

    cache = rec.meta_json.to_h['header_media_cache']
    return nil if cache.blank?
    return nil if cache['media_url'] != media_url # la URL rota cada ~24-48h -> invalida
    return nil if cache['cached_at'].to_i < (Time.now.utc - MEDIA_ID_TTL).to_i

    cache['media_id'].presence
  end

  def cache_media_id(media_id)
    rec = template_record
    return if rec.blank?

    meta = rec.meta_json.to_h
    meta['header_media_cache'] = { 'media_id' => media_id, 'media_url' => media_url, 'cached_at' => Time.now.utc.to_i }
    rec.update_column(:meta_json, meta)
  rescue StandardError => e
    Rails.logger.warn "[WA TemplateMedia] cache write failed: #{e.message}"
  end

  # ── Helpers de canal ──────────────────────────────────────────────────────
  def api_key
    channel.provider_config['api_key']
  end

  def phone_number_id
    channel.provider_config['phone_number_id']
  end

  def graph_base
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end

  def default_content_type
    { 'image' => 'image/jpeg', 'video' => 'video/mp4', 'document' => 'application/pdf' }[media_type.to_s.downcase] || 'image/jpeg'
  end

  def extension_for(content_type)
    {
      'image/jpeg' => 'jpg', 'image/png' => 'png', 'video/mp4' => 'mp4',
      'application/pdf' => 'pdf'
    }[content_type.to_s.split(';').first] || 'bin'
  end
end
