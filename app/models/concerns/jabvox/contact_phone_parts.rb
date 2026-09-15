# frozen_string_literal: true

# Mantiene sincronizadas las tres piezas del teléfono de un contacto:
#
#   phone_country_code_jabvox  "+57"
#   phone_national_jabvox      "3001234567"
#   phone_number               "+573001234567"   <- identidad, la que deduplica
#
# El prefijo va en columna propia y NO en la `country_code` de upstream: Chatwoot
# usa esa para el país ISO y la reescribe en cada guardado (Contacts::SyncAttributes).
#
# La fuente de verdad es SIEMPRE phone_number (E.164): las otras dos se derivan de
# él al guardar. Así ningún código que escriba solo phone_number (importaciones,
# webhooks, canales de Chatwoot) puede dejar las piezas desincronizadas.
#
# Para construir el teléfono a partir del país y el número local, el formulario
# usa assign_phone_from_parts, que produce el E.164 y deja que este callback
# derive el resto.
module Jabvox::ContactPhoneParts
  extend ActiveSupport::Concern

  # País por defecto con el que se reparan los teléfonos heredados que no llevan
  # código de país. Configurable por entorno para instalaciones de otro país.
  LEGACY_COUNTRY_ISO = ENV.fetch('JABVOX_DEFAULT_COUNTRY', 'CO')

  included do
    # Repara ANTES de validar los teléfonos heredados que se guardaron saltando
    # la validación (el import antiguo usaba save!(validate: false)). Sin esto,
    # un contacto con "573001234567" o "3001234567" quedaba BLOQUEADO: no se
    # podía editar ni su nombre, porque la validación rechazaba el teléfono.
    before_validation :repair_legacy_jabvox_phone
    before_save :sync_jabvox_phone_parts, if: :will_save_change_to_phone_number?
  end

  # Asigna el teléfono a partir del país (ISO) y el número local tal como lo
  # teclea el usuario. El prefijo sale del país, nunca del número.
  # Devuelve false si no se puede formar un E.164 válido.
  def assign_phone_from_parts(country_iso, national)
    e164 = Jabvox::PhoneParts.join(country_iso, national)
    return false if e164.blank?

    self.phone_number = e164
    true
  end

  # El teléfono en sus tres piezas, para las vistas y la API.
  def phone_parts_jabvox
    {
      country_code: phone_country_code_jabvox.presence,
      national: phone_national_jabvox.presence,
      e164: phone_number.presence
    }
  end

  private

  # Normaliza un teléfono heredado a E.164 SOLO cuando el usuario no lo está
  # cambiando: así una edición de nombre deja de fallar y el número queda
  # arreglado de paso. Si el valor no se puede normalizar, se deja intacto y la
  # validación decide — nunca se inventa un número.
  def repair_legacy_jabvox_phone
    return if phone_number.blank?
    return if phone_number.match?(Jabvox::LeadIdentityService::E164)
    # Si el usuario está escribiendo un teléfono nuevo, que la validación le
    # avise del error en vez de corregirlo a sus espaldas.
    return if persisted? && will_save_change_to_phone_number?

    repaired = Jabvox::LeadIdentityService.normalize_phone(phone_number, LEGACY_COUNTRY_ISO).value
    self.phone_number = repaired if repaired.present?
  end

  def sync_jabvox_phone_parts
    if phone_number.blank?
      self.phone_country_code_jabvox = nil
      self.phone_national_jabvox = nil
      return
    end

    parts = Jabvox::PhoneParts.split(phone_number)
    return if parts.nil?

    self.phone_country_code_jabvox = parts[:country_code]
    self.phone_national_jabvox = parts[:national]
  end
end
