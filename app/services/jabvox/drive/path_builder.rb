# frozen_string_literal: true

# Construye las rutas legibles del Drive (en MinIO y en las carpetas lógicas de la
# UI) a partir del contacto y la bandeja. Estructura:
#
#   contactos/<nombre>-<telefono>-<username>/<nombre-bandeja>/<archivo>
#
# El slug del contacto incluye lo que tenga (nombre, teléfono, username/identifier);
# las partes vacías se omiten. El id del contacto se añade al final para garantizar
# unicidad (dos "Ana" distintas no colisionan) sin estorbar la búsqueda por nombre.
#
# Objetivo: poder ubicar/buscar el contacto por nombre, número o username, y agrupar
# sus adjuntos por la bandeja (inbox) en la que escribió/recibió.
module Jabvox::Drive::PathBuilder
  module_function

  ROOT = 'contactos'

  # Carpeta del contacto: "<nombre>-<telefono>-<username>-<id>".
  def contact_slug(contact)
    return "sin-contacto-#{SecureRandom.hex(4)}" if contact.nil?

    parts = [contact.name, contact_phone(contact), contact_username(contact)]
            .map { |p| slug(p) }
            .reject(&:blank?)
    parts << contact.id.to_s # unicidad estable
    parts.join('-')
  end

  # Carpeta de la bandeja: nombre de la inbox (slug). Si no hay, el tipo de canal.
  def inbox_slug(inbox)
    return 'bandeja' if inbox.nil?

    name = slug(inbox.name)
    name.presence || channel_slug(inbox)
  end

  # Prefijo completo (relativo al bucket, SIN el acct-<id>/ que añade StorageService):
  #   contactos/<contacto>/<bandeja>/
  def relative_prefix(contact:, inbox:)
    "#{ROOT}/#{contact_slug(contact)}/#{inbox_slug(inbox)}/"
  end

  # Ruta lógica para las carpetas de la UI (jabvox_drive_folders):
  #   /contactos/<contacto>/<bandeja>/
  def logical_path(contact:, inbox:)
    "/#{relative_prefix(contact: contact, inbox: inbox)}"
  end

  # --- helpers internos ---

  # Normaliza a un segmento seguro para una key de S3 / nombre de carpeta:
  # minúsculas, sin acentos, espacios y símbolos -> guion, sin barras.
  def slug(value)
    str = value.to_s.strip.downcase
    return '' if str.blank?

    str = I18n.transliterate(str) # quita acentos (á->a, ñ->n)
    str.gsub(%r{[/\\]}, '-')      # nunca barras (romperían la jerarquía)
       .gsub(/[^a-z0-9]+/, '-').squeeze('-')           # colapsa guiones repetidos
       .delete_prefix('-').delete_suffix('-')
       .first(60)                 # tope por segmento
  end

  def contact_phone(contact)
    phone = contact.try(:phone_number).presence
    phone&.to_s&.gsub(/[^0-9]/, '') # solo dígitos (buscable)
  end

  # Username/identificador del canal (Instagram/Telegram/etc.) si existe.
  def contact_username(contact)
    contact.try(:identifier).presence ||
      contact.try(:additional_attributes)&.then { |a| a['username'] || a['screen_name'] }
  end

  def channel_slug(inbox)
    type = inbox.channel_type.to_s.demodulize.underscore # Channel::Whatsapp -> whatsapp
    slug(type).presence || 'bandeja'
  end
end
