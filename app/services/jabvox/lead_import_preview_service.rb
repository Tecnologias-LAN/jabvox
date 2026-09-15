# frozen_string_literal: true

# Analiza las filas de una importación ANTES de escribir nada y devuelve el
# resumen que el usuario ve en la vista previa:
#
#   - nuevas          : se crearán
#   - duplicadas_bd   : ya existen en la cuenta (mismo teléfono o mismo correo)
#   - duplicadas_arch : repetidas dentro del propio archivo
#   - invalidas       : sin identidad utilizable (ni teléfono ni correo válidos)
#   - con_prefijo     : el archivo ya traía el prefijo internacional
#
# No escribe en base de datos. Es de solo lectura y está acotado por cuenta.
class Jabvox::LeadImportPreviewService
  # Tope de filas que se analizan en una sola pasada. Protege el endpoint de
  # vista previa: un archivo mayor se importa igual, pero la vista previa solo
  # detalla hasta aquí (el resumen sí cuenta el total real).
  MAX_ROWS = 20_000

  # Máximo de filas detalladas que se devuelven al frontend, para que la
  # respuesta no crezca sin límite con archivos grandes.
  MAX_DETAIL = 500

  Row = Struct.new(:index, :name, :email, :phone, :phone_original, :status,
                   :existing_contact_id, :existing_name, :notice,
                   keyword_init: true)

  # rows: [{ 'name' =>, 'email' =>, 'phone_number' => }, ...] tal como vienen del archivo.
  def initialize(account, rows, country_iso:)
    @account = account
    @rows = Array(rows).first(MAX_ROWS)
    @total_received = Array(rows).size
    @country_iso = country_iso.to_s.strip.upcase
  end

  def call
    normalized = normalize_rows
    index = build_existing_index(normalized)
    classify(normalized, index)

    {
      country: @country_iso,
      dial_code: identity.dial_code_for(@country_iso),
      total_rows: @total_received,
      analyzed_rows: normalized.size,
      truncated: @total_received > normalized.size,
      counts: @counts,
      rows: normalized.first(MAX_DETAIL).map { |row| serialize(row) }
    }
  end

  private

  def identity = Jabvox::LeadIdentityService

  def normalize_rows
    @rows.each_with_index.map do |raw, idx|
      row = raw.respond_to?(:with_indifferent_access) ? raw.with_indifferent_access : raw.to_h.with_indifferent_access
      phone = identity.normalize_phone(row[:phone_number].presence || row[:phone], @country_iso)
      Row.new(
        index: idx,
        name: row[:name].to_s.strip,
        email: identity.normalize_email(row[:email]),
        phone: phone.value,
        phone_original: phone.original,
        notice: (phone.had_prefix? ? 'prefijo_en_archivo' : nil)
      )
    end
  end

  def build_existing_index(rows)
    identity.existing_index(
      @account,
      phones: rows.filter_map(&:phone),
      emails: rows.filter_map(&:email)
    )
  end

  # Clasifica cada fila. El orden importa: primero se descarta lo que no tiene
  # identidad, luego lo repetido dentro del archivo, y solo al final se mira la
  # base de datos — así una fila repetida en el archivo no cuenta dos veces
  # como duplicada de base.
  def classify(rows, index)
    @counts = { nuevas: 0, duplicadas_bd: 0, duplicadas_archivo: 0, invalidas: 0, con_prefijo: 0 }
    seen_phones = {}
    seen_emails = {}

    rows.each do |row|
      @counts[:con_prefijo] += 1 if row.notice == 'prefijo_en_archivo'
      row.status = classify_row(row, index, seen_phones, seen_emails)
      @counts[count_key(row.status)] += 1
      remember(row, seen_phones, seen_emails)
    end
  end

  def classify_row(row, index, seen_phones, seen_emails)
    return 'invalida' if row.phone.blank? && row.email.blank?
    return 'duplicada_archivo' if duplicate_in_file?(row, seen_phones, seen_emails)

    existing = identity.match_existing(index, phone: row.phone, email: row.email)
    return 'nueva' unless existing

    row.existing_contact_id = existing.id
    row.existing_name = existing.name
    'duplicada_bd'
  end

  def duplicate_in_file?(row, seen_phones, seen_emails)
    (row.phone.present? && seen_phones.key?(row.phone)) ||
      (row.email.present? && seen_emails.key?(row.email))
  end

  def remember(row, seen_phones, seen_emails)
    seen_phones[row.phone] = true if row.phone.present?
    seen_emails[row.email] = true if row.email.present?
  end

  def count_key(status)
    { 'nueva' => :nuevas, 'duplicada_bd' => :duplicadas_bd,
      'duplicada_archivo' => :duplicadas_archivo, 'invalida' => :invalidas }[status]
  end

  def serialize(row)
    {
      index: row.index,
      name: row.name,
      email: row.email,
      phone: row.phone,
      phone_original: row.phone_original,
      status: row.status,
      notice: row.notice,
      existing_contact_id: row.existing_contact_id,
      existing_name: row.existing_name
    }
  end
end
