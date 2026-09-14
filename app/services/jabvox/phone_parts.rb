# frozen_string_literal: true

# Separa un teléfono E.164 en las tres piezas con las que Jabvox trabaja:
#
#   country_code -> "+57"            el prefijo, que SIEMPRE sale del país elegido
#   national     -> "3001234567"     el número local, como lo teclea el usuario
#   e164         -> "+573001234567"  la identidad (lo que deduplica)
#
# El corte se hace contra el catálogo real de códigos de marcación y siempre por
# el prefijo MÁS LARGO que encaje: "+1684" (Samoa Americana) antes que "+1", para
# que un número de allí no se parta como si fuera de Estados Unidos.
module Jabvox::PhoneParts
  module_function

  # Descompone un E.164. Devuelve nil si no lo es.
  def split(e164)
    value = e164.to_s.strip
    return nil unless value.match?(Jabvox::LeadIdentityService::E164)

    digits = value.delete_prefix('+')
    dial = longest_dial_code_for(digits)
    return { country_code: nil, national: digits, e164: value } if dial.nil?

    { country_code: "+#{dial}", national: digits.delete_prefix(dial), e164: value }
  end

  # Arma el E.164 a partir de las partes que envía el formulario. Devuelve nil si
  # no se puede formar uno válido — nunca un número a medias.
  def join(country_iso, national)
    Jabvox::LeadIdentityService.normalize_phone(national, country_iso).value
  end

  # Códigos de marcación ordenados de más largo a más corto, para que el corte
  # elija siempre el más específico. Se calcula una sola vez.
  def dial_codes_by_length
    @dial_codes_by_length ||= Jabvox::LeadIdentityService::DIAL_CODES
                              .values.uniq.sort_by { |code| -code.length }
  end

  def longest_dial_code_for(digits)
    dial_codes_by_length.find do |code|
      # El resto tras quitar el prefijo debe seguir pareciendo un número local,
      # no quedar vacío.
      digits.start_with?(code) && digits.length > code.length
    end
  end
end
