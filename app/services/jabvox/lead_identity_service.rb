# frozen_string_literal: true

# Fuente de verdad ÚNICA para decidir cuándo dos leads son "el mismo".
#
# Reglas de producto (no se suponen coincidencias aproximadas):
#   - Un lead se identifica por TELÉFONO y/o CORREO, ambos normalizados.
#   - La igualdad es EXACTA. "+573001234567" y "+573001234568" son leads
#     DISTINTOS aunque difieran en un dígito. No hay fuzzy matching.
#   - El prefijo internacional NUNCA se adivina a partir del número: sale del
#     país que el usuario elige al importar. Si un número ya viene con prefijo
#     (+57..., 57...), se detecta y se reporta para que el usuario lo suba sin
#     prefijo, pero jamás se inventa uno distinto al del país elegido.
#
# Todos los caminos de importación (CSV de contactos, portal de afiliados,
# lead-import desde BD externa) deben pasar por aquí para que la deduplicación
# sea idéntica en los tres.
class Jabvox::LeadIdentityService
  # E.164: '+' seguido de 1..15 dígitos, el primero distinto de 0.
  E164 = /\A\+[1-9]\d{1,14}\z/

  # Resultado de normalizar un teléfono.
  #   value    : el E.164 final, o nil si no se pudo formar uno válido
  #   status   : :ok | :had_prefix | :invalid | :blank
  #   original : lo que trajo el archivo, tal cual (para mostrarlo en la vista previa)
  PhoneResult = Struct.new(:value, :status, :original, keyword_init: true) do
    def ok? = !value.nil?
    def had_prefix? = status == :had_prefix
  end

  class << self
    # Código de marcación ('57') del país ISO ('CO'). nil si el país no existe.
    def dial_code_for(country_iso)
      iso = country_iso.to_s.strip.upcase
      return nil if iso.blank?

      DIAL_CODES[iso]
    end

    def valid_country?(country_iso)
      dial_code_for(country_iso).present?
    end

    # Normaliza un teléfono al E.164 usando el prefijo del país elegido.
    #
    # El prefijo SIEMPRE proviene de country_iso. Los tres casos del mundo real:
    #   "3001234567"     -> +573001234567           (status :ok)
    #   "+573001234567"  -> +573001234567           (status :had_prefix)
    #   "573001234567"   -> +573001234567           (status :had_prefix)
    #
    # :had_prefix marca las filas donde el archivo YA traía el prefijo, para
    # avisar al usuario que debería subirlas sin él. El valor se acepta igual
    # cuando el prefijo coincide con el país elegido; si trae un prefijo de otro
    # país se respeta ese número tal cual (es un teléfono extranjero legítimo),
    # pero la fila se marca igual para que el usuario lo revise.
    def normalize_phone(raw, country_iso)
      original = raw.to_s.strip
      return PhoneResult.new(value: nil, status: :blank, original: original) if original.blank?

      digits = original.gsub(/[^\d+]/, '')
      # Un '+' solo es válido al inicio; cualquier otro es basura del archivo.
      digits = "+#{digits.delete('+')}" if digits.start_with?('+')
      digits = digits.delete('+') unless digits.start_with?('+')

      dial = dial_code_for(country_iso)
      build_phone_result(digits, dial, original)
    end

    # Normaliza un correo. Devuelve nil si está vacío o no es un correo válido:
    # un valor inválido no puede usarse como identidad, así que no deduplica.
    def normalize_email(raw)
      email = raw.to_s.strip.downcase
      return nil if email.blank?
      return nil unless email.match?(URI::MailTo::EMAIL_REGEXP)

      email
    end

    # Busca en la cuenta los contactos que ya usan alguno de estos teléfonos o
    # correos. Devuelve { phones: { '+57...' => contact }, emails: { 'a@b.c' => contact } }.
    #
    # Siempre parte de account.contacts: nunca Contact.where(...) global, para
    # que la deduplicación no pueda cruzar cuentas.
    def existing_index(account, phones: [], emails: [])
      phones = Array(phones).compact.uniq
      emails = Array(emails).compact.uniq

      {
        phones: index_by_column(account, :phone_number, phones),
        emails: index_by_column(account, :email, emails)
      }
    end

    # El contacto existente que corresponde a esta identidad, si lo hay.
    # Teléfono primero (es la identidad más fuerte en el CRM), luego correo.
    def match_existing(index, phone: nil, email: nil)
      (phone && index[:phones][phone]) || (email && index[:emails][email])
    end

    private

    def build_phone_result(digits, dial, original)
      return PhoneResult.new(value: nil, status: :invalid, original: original) if digits.delete('+').blank?

      # Ya trae prefijo cuando: empieza por '+', o no hay país con el que
      # anteponer nada, o los dígitos arrancan con el código del país y son
      # demasiado largos para ser un número local ("573001234567").
      return finish(digits, :had_prefix, original) if digits.start_with?('+')
      return finish("+#{digits}", :had_prefix, original) if carries_dial_code?(digits, dial)

      # Número local: el prefijo lo pone el país elegido. Se quitan los ceros de
      # marcación nacional ("03001234567" -> "3001234567").
      finish("+#{dial}#{digits.sub(/\A0+/, '')}", :ok, original)
    end

    # ¿Los dígitos ya llevan el código de país incorporado?
    def carries_dial_code?(digits, dial)
      return true if dial.blank?

      digits.start_with?(dial) && digits.length > dial.length + MIN_LOCAL_DIGITS
    end

    def finish(candidate, status, original)
      return PhoneResult.new(value: nil, status: :invalid, original: original) unless candidate.match?(E164)

      PhoneResult.new(value: candidate, status: status, original: original)
    end

    # Un número local plausible tiene al menos esta cantidad de dígitos. Se usa
    # para distinguir "573001234567" (prefijo + local) de un local que por
    # casualidad empieza por 57.
    MIN_LOCAL_DIGITS = 6

    def index_by_column(account, column, values)
      return {} if values.empty?

      # in_batches sobre los valores: un archivo de 50k filas no puede generar
      # un IN (...) de 50k elementos en una sola consulta.
      values.each_slice(1_000).with_object({}) do |slice, acc|
        account.contacts.where(column => slice).find_each do |contact|
          key = contact.public_send(column)
          acc[key] ||= contact
        end
      end
    end
  end

  # Mapa ISO -> código de marcación, derivado del mismo catálogo que usa el
  # frontend (app/javascript/shared/constants/countries.js) para que el prefijo
  # que muestra la UI y el que aplica el backend nunca se separen.
  DIAL_CODES = JSON.parse(
    Rails.root.join('config/jabvox/country_dial_codes.json').read
  ).freeze
end
