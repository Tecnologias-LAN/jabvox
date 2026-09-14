# frozen_string_literal: true

# Extensión Jabvox del DataImportJob: normaliza la identidad de cada fila
# (teléfono con el prefijo del país elegido + correo) y decide qué hacer con las
# filas que ya existen en la cuenta.
#
# Se mantiene fuera del job de upstream para no tocar su lógica de importación.
#
# Reglas (ver Jabvox::LeadIdentityService):
#   - La igualdad es EXACTA sobre el teléfono normalizado o el correo. Dos
#     números que difieren en un dígito son leads distintos.
#   - El prefijo sale del país elegido, nunca se adivina del número.
#   - Duplicado en base: se actualiza o se omite según la política elegida por
#     el usuario en la vista previa; nunca se crea un lead repetido.
#   - Duplicado dentro del mismo archivo: solo se procesa la primera aparición.
module Jabvox::DataImportIdentity
  extend ActiveSupport::Concern

  # Prepara el estado por importación. Se llama una vez al inicio del job.
  def setup_jabvox_identity
    @jabvox_country = @data_import.import_country_jabvox
    @jabvox_policy = @data_import.duplicate_policy_jabvox
    @jabvox_seen = { phones: {}, emails: {} }
    @jabvox_stats = { created: 0, updated: 0, duplicates_skipped: 0,
                      duplicates_in_file: 0, invalid: 0, phones_with_prefix: 0 }
  end

  # Normaliza teléfono y correo de la fila EN EL SITIO, para que tanto el
  # ContactManager de upstream como la deduplicación trabajen sobre el mismo
  # valor canónico. Devuelve la identidad calculada.
  def jabvox_normalize_row!(row_hash)
    phone = Jabvox::LeadIdentityService.normalize_phone(row_hash[:phone_number], @jabvox_country)
    email = Jabvox::LeadIdentityService.normalize_email(row_hash[:email])

    @jabvox_stats[:phones_with_prefix] += 1 if phone.had_prefix?

    row_hash[:phone_number] = phone.value
    row_hash[:email] = email
    row_hash.delete(:phone_number) if phone.value.nil?
    row_hash.delete(:email) if email.nil?

    # Se guarda la referencia para poder alinear una fila repetida con la
    # identidad de su primera aparición (ver jabvox_align_with_first_occurrence!).
    @jabvox_current_row = row_hash
    { phone: phone.value, email: email }
  end

  # :process | :skip — qué hacer con esta fila.
  #
  # Cada decisión suma al resumen que ve el usuario al terminar la importación.
  #
  # Ojo con la fila repetida DENTRO del archivo: se cuenta como duplicada en el
  # resumen, pero se sigue procesando. El ContactManager la resuelve contra el
  # mismo contacto (no crea uno nuevo) y así no se pierden los datos extra que
  # trae esa segunda fila — en particular sus etiquetas.
  def jabvox_row_decision(identity)
    return record_outcome(:invalid, :skip) if identity[:phone].blank? && identity[:email].blank?

    if jabvox_seen_in_file?(identity)
      @jabvox_stats[:duplicates_in_file] += 1
      # Se sigue procesando para no perder los datos extra de esta segunda fila
      # (sus etiquetas), pero forzando la MISMA identidad que la primera
      # aparición: sin esto, una fila con el mismo teléfono y un correo nuevo
      # crearía un contacto duplicado (el ContactManager busca por correo antes
      # que por teléfono).
      jabvox_align_with_first_occurrence!(identity)
      return :process
    end

    remember_in_file(identity)
    existing = jabvox_existing_contact(identity)
    return record_outcome(:created, :process) if existing.nil?
    # Duplicado en base con política 'skip': el lead existente NO se toca.
    return record_outcome(:duplicates_skipped, :skip) if @jabvox_policy == 'skip'

    record_outcome(:updated, :process)
  end

  # Filas que existían ya en la cuenta y se omitieron por política. Se procesaron
  # (se decidió no tocarlas), así que cuentan como procesadas en el total.
  def jabvox_skipped_duplicates
    @jabvox_stats[:duplicates_skipped]
  end

  # El resumen final, guardado en data_import.stats para que el frontend lo
  # muestre: cuántos se montaron, cuántos se actualizaron y cuántos no entraron
  # por ser duplicados.
  def jabvox_persist_stats
    @data_import.update!(stats: (@data_import.stats || {}).merge(
      'jabvox' => @jabvox_stats.stringify_keys.merge(
        'country' => @jabvox_country, 'duplicate_policy' => @jabvox_policy
      )
    ))
  end

  private

  def record_outcome(key, decision)
    @jabvox_stats[key] += 1
    decision
  end

  def jabvox_seen_in_file?(identity)
    (identity[:phone].present? && @jabvox_seen[:phones].key?(identity[:phone])) ||
      (identity[:email].present? && @jabvox_seen[:emails].key?(identity[:email]))
  end

  def remember_in_file(identity)
    @jabvox_seen[:phones][identity[:phone]] = identity if identity[:phone].present?
    @jabvox_seen[:emails][identity[:email]] = identity if identity[:email].present?
  end

  # Reescribe la fila con la identidad de su primera aparición en el archivo,
  # para que el ContactManager resuelva contra el MISMO contacto y fusione en
  # lugar de crear otro.
  def jabvox_align_with_first_occurrence!(identity)
    first = @jabvox_seen[:phones][identity[:phone]] || @jabvox_seen[:emails][identity[:email]]
    return unless first

    identity[:phone] = first[:phone]
    identity[:email] = first[:email]
    @jabvox_current_row[:phone_number] = first[:phone] if @jabvox_current_row
    @jabvox_current_row[:email] = first[:email] if @jabvox_current_row
  end

  # Siempre a través de account.contacts: la deduplicación nunca puede cruzar
  # cuentas.
  def jabvox_existing_contact(identity)
    account = @data_import.account
    contact = account.contacts.find_by(phone_number: identity[:phone]) if identity[:phone].present?
    # from_email: la búsqueda por correo debe ser insensible a mayúsculas, igual
    # que la validación de unicidad del modelo.
    contact ||= account.contacts.from_email(identity[:email]) if identity[:email].present?
    contact
  end
end
