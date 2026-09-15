# frozen_string_literal: true

# Normaliza a E.164 los teléfonos heredados (ver lib/tasks/jabvox_phone_normalize.rake).
#
# Reglas que NO se rompen:
#   - Solo toca filas que no son E.164; lo ya correcto se deja intacto.
#   - Nunca fusiona ni borra contactos: si el número normalizado chocaría con
#     otro contacto de la misma cuenta, esa fila se salta y se reporta.
#   - Escribe con update_columns (sin callbacks ni validaciones) para no disparar
#     eventos, webhooks ni trabajos en segundo plano sobre datos históricos.
#   - En modo simulación no escribe absolutamente nada.
class Jabvox::PhoneNormalizeTask
  BATCH_SIZE = 1_000

  Report = Struct.new(:scanned, :normalized, :conflicts, :unparseable, :samples,
                      keyword_init: true)

  def initialize(apply: false, account_id: nil, country: 'CO', limit: nil, logger: nil)
    @apply = apply
    @account_id = account_id
    @country = country.to_s.strip.upcase
    @limit = limit
    @logger = logger || Rails.logger
  end

  def run
    report = build_report
    print_summary(report)
    report
  end

  # Expuesto para las pruebas: recorre y devuelve el resultado sin imprimir.
  def build_report
    report = Report.new(scanned: 0, normalized: 0, conflicts: 0, unparseable: 0, samples: [])
    processed = 0

    candidates.find_each(batch_size: BATCH_SIZE) do |contact|
      break if @limit && processed >= @limit

      processed += 1
      report.scanned += 1
      process(contact, report)
    end
    report
  end

  private

  # Solo contactos con teléfono que NO esté ya en E.164. El filtro va en SQL para
  # no traer la tabla entera a memoria.
  def candidates
    scope = Contact.where.not(phone_number: [nil, ''])
                   .where.not("phone_number ~ '^\\+[1-9][0-9]{1,14}$'")
    scope = scope.where(account_id: @account_id) if @account_id.present?
    scope.order(:id)
  end

  def process(contact, report)
    normalized = Jabvox::LeadIdentityService.normalize_phone(contact.phone_number, @country).value

    if normalized.blank?
      report.unparseable += 1
      record_sample(report, contact, nil, 'no_normalizable')
      return
    end

    if taken_by_another?(contact, normalized)
      report.conflicts += 1
      record_sample(report, contact, normalized, 'conflicto_con_otro_contacto')
      return
    end

    apply_change(contact, normalized)
    report.normalized += 1
    record_sample(report, contact, normalized, 'normalizado')
  end

  # ¿El número ya normalizado pertenece a OTRO contacto de la misma cuenta?
  # En ese caso son dos filas de la misma persona: no se fusionan aquí (eso es
  # una decisión del usuario), se reportan para revisión manual.
  def taken_by_another?(contact, normalized)
    Contact.where(account_id: contact.account_id, phone_number: normalized)
           .where.not(id: contact.id)
           .exists?
  end

  def apply_change(contact, normalized)
    return unless @apply

    parts = Jabvox::PhoneParts.split(normalized) || {}
    # update_columns: sin callbacks ni validaciones — no queremos disparar
    # eventos ni webhooks al reparar datos históricos.
    contact.update_columns( # rubocop:disable Rails/SkipsModelValidations
      phone_number: normalized,
      phone_country_code_jabvox: parts[:country_code],
      phone_national_jabvox: parts[:national]
    )
  end

  # Se guardan unas pocas filas de ejemplo para que el informe sea revisable.
  def record_sample(report, contact, normalized, status)
    return if report.samples.size >= 20

    report.samples << { id: contact.id, account_id: contact.account_id,
                        before: contact.phone_number, after: normalized, status: status }
  end

  def print_summary(report)
    mode = @apply ? 'APLICADO' : 'SIMULACIÓN (no se escribió nada)'
    @logger.info("[PhoneNormalize] #{mode} país=#{@country}")
    @logger.info("[PhoneNormalize] revisados=#{report.scanned} normalizados=#{report.normalized} " \
                 "conflictos=#{report.conflicts} no_normalizables=#{report.unparseable}")
    report.samples.each do |s|
      @logger.info("[PhoneNormalize]   ##{s[:id]} #{s[:before].inspect} -> #{s[:after].inspect} (#{s[:status]})")
    end
    return if @apply

    @logger.info('[PhoneNormalize] Para aplicar de verdad: rake jabvox:phones:normalize APPLY=1')
  end
end
