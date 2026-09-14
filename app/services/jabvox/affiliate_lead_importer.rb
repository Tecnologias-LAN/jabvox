# frozen_string_literal: true

# Crea leads de un afiliado aplicando las reglas de identidad de Jabvox.
#
# Lo usan tanto la carga masiva (job) como el alta manual (controlador), para que
# las dos vías se comporten igual. El afiliado NUNCA actualiza un lead que ya
# existe: si el teléfono o el correo ya están en la cuenta, la fila se cuenta
# como duplicada y no se toca nada.
class Jabvox::AffiliateLeadImporter
  Result = Struct.new(:outcome, :contact, keyword_init: true)

  def initialize(account:, affiliate:, country_iso:, campaign_name: nil)
    @account = account
    @affiliate = affiliate
    @country_iso = country_iso.to_s.strip.upcase
    @campaign_name = campaign_name.to_s.strip.presence
    @counters = { rows_ok: 0, rows_duplicated: 0, rows_failed: 0 }
    @seen = { phones: {}, emails: {} }
  end

  attr_reader :counters

  # Importa una fila del archivo. Devuelve :ok, :duplicated o :failed y actualiza
  # los contadores del resumen.
  def import_row(row)
    identity = identity_for(row)
    outcome = create_or_skip(identity, row).outcome
    @counters[counter_key(outcome)] += 1
    outcome
  end

  # Alta de un solo lead (portal manual). Deja registro de la operación para que
  # el historial del afiliado muestre también las altas manuales.
  def import_one(name:, phone_raw:, email_raw:, city: nil)
    identity = build_identity(name, phone_raw, email_raw, city)
    result = create_or_skip(identity, {})
    log_manual_import(result.outcome)
    result
  end

  # Identidad normalizada de una fila, sin tocar base de datos. Expuesta para que
  # el controlador valide antes de encolar.
  def identity_for(row)
    build_identity(row['name'], row['phone'] || row['phone_number'], row['email'], row['city'])
  end

  private

  def build_identity(name, phone_raw, email_raw, city)
    {
      name: name.to_s.strip,
      phone: Jabvox::LeadIdentityService.normalize_phone(phone_raw, @country_iso).value,
      email: Jabvox::LeadIdentityService.normalize_email(email_raw),
      city: city.to_s.strip.presence
    }
  end

  def create_or_skip(identity, _row)
    return Result.new(outcome: :failed) if identity[:name].blank?
    # Sin teléfono ni correo no hay forma de garantizar que no sea un duplicado,
    # así que no se monta.
    return Result.new(outcome: :failed) if identity[:phone].blank? && identity[:email].blank?
    return Result.new(outcome: :duplicated) if seen_in_file?(identity) || existing?(identity)

    remember(identity)
    Result.new(outcome: :ok, contact: create_lead!(identity))
  rescue ActiveRecord::RecordNotUnique
    # Carrera con otra subida: el contacto lo creó alguien más entre la
    # comprobación y el insert. Es un duplicado, no un fallo.
    Result.new(outcome: :duplicated)
  rescue StandardError => e
    Rails.logger.error("[AffiliateLeadImporter] afiliado=#{@affiliate.id} #{e.class}: #{e.message}")
    Result.new(outcome: :failed)
  end

  # Registro de un alta manual (1 fila). No falla la operación si el registro no
  # se puede crear: el lead ya existe y es lo que importa.
  def log_manual_import(outcome)
    JabvoxAffiliateImport.create!(
      account: @account, jabvox_affiliate: @affiliate, import_type: :manual,
      status: :completed, completed_at: Time.current, country_jabvox: @country_iso,
      rows_total: 1, rows_ok: outcome == :ok ? 1 : 0,
      rows_duplicated: outcome == :duplicated ? 1 : 0,
      rows_failed: outcome == :failed ? 1 : 0
    )
  rescue StandardError => e
    Rails.logger.warn("[AffiliateLeadImporter] no se pudo registrar alta manual: #{e.message}")
  end

  def counter_key(outcome)
    { ok: :rows_ok, duplicated: :rows_duplicated, failed: :rows_failed }[outcome]
  end

  def seen_in_file?(identity)
    (identity[:phone].present? && @seen[:phones].key?(identity[:phone])) ||
      (identity[:email].present? && @seen[:emails].key?(identity[:email]))
  end

  def remember(identity)
    @seen[:phones][identity[:phone]] = true if identity[:phone].present?
    @seen[:emails][identity[:email]] = true if identity[:email].present?
  end

  # Siempre sobre account.contacts: un afiliado no puede chocar con contactos de
  # otra cuenta ni consultarlos.
  def existing?(identity)
    scope = @account.contacts
    return true if identity[:phone].present? && scope.exists?(phone_number: identity[:phone])

    identity[:email].present? && scope.exists?(email: identity[:email])
  end

  def create_lead!(identity)
    contact = nil
    ActiveRecord::Base.transaction do
      contact = @account.contacts.create!(
        name: identity[:name], email: identity[:email], phone_number: identity[:phone],
        contact_type: :lead,
        additional_attributes: { 'country_code' => @country_iso, 'city' => identity[:city] }.compact,
        custom_attributes: {}
      )
      lead = JabvoxLead.find_or_initialize_by(account: @account, contact: contact)
      lead.jabvox_affiliate = @affiliate
      lead.jabvox_campaign = campaign if campaign
      lead.save!
    end
    contact
  end

  # Campaña elegida para la importación, resuelta una sola vez y siempre dentro
  # de la cuenta del afiliado.
  def campaign
    return @campaign if defined?(@campaign)

    @campaign = @campaign_name && JabvoxCampaign.find_by(account: @account, name_jabvox: @campaign_name)
  end
end
