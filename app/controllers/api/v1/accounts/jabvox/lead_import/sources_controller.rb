# CRUD + acciones del lead-import; larga por el nº de endpoints, cada método es simple.
# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::Jabvox::LeadImport::SourcesController < Api::V1::Accounts::Jabvox::LeadImport::BaseController
  # Un 'syncing' más viejo que esto se considera colgado (worker muerto) y puede relanzarse.
  SYNC_STALE_AFTER = 15.minutes

  before_action :set_source, only: %i[show update destroy test_connection tables columns sync sync_status]

  def index
    render json: { sources: scoped.order(:name_jabvox).map { |s| serialize(s) } }
  end

  def show
    render json: serialize(@source)
  end

  def create
    source = scoped.new(source_params)
    source.created_by = current_user
    source.save!
    render json: serialize(source), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    # A blank password means "keep current" — don't overwrite the encrypted value.
    @source.update!(source_params.except(*blank_password_key))
    render json: serialize(@source)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  # DELETE /sources/:id?purge_leads= — removes the connection. When purge_leads is
  # true, the leads it imported are moved to the restorable trash first (they can be
  # restored from super admin within the retention window); otherwise leads are kept.
  def destroy
    if ActiveModel::Type::Boolean.new.cast(params[:purge_leads])
      Jabvox::LeadImport::TrashService.new(Current.account)
                                      .trash_source_leads(@source, deleted_by: current_user)
    end
    @source.destroy!
    head :no_content
  end

  # POST /sources/:id/test_connection — validates connectivity (SSRF-guarded).
  def test_connection
    render json: Jabvox::Analytics::ConnectionTestService.new(@source).call
  end

  # POST /sources/test_connection — test unsaved params.
  def test_connection_unsaved
    source = scoped.new(source_params)
    render json: Jabvox::Analytics::ConnectionTestService.new(source).call
  end

  # GET /sources/:id/tables — external tables + columns for the mapping UI.
  def tables
    render json: { tables: Jabvox::LeadImport::SchemaService.new(@source).tables }
  rescue StandardError => e
    render json: { error: sanitized(e) }, status: :unprocessable_entity
  end

  # GET /sources/:id/columns?table= — columns of one external table.
  def columns
    cols = Jabvox::LeadImport::SchemaService.new(@source).columns(params[:table])
    render json: { columns: cols }
  rescue StandardError => e
    render json: { error: sanitized(e) }, status: :unprocessable_entity
  end

  # GET /sources/lead_fields — standard + custom lead fields available for mapping.
  def lead_fields
    render json: { standard: standard_lead_fields, custom: custom_lead_fields }
  end

  # POST /sources/create_custom_field — creates a lead custom column (type chosen
  # by user). Idempotent: if a column with the same key already exists (e.g. two
  # admins on the same account do it at once, or a prior sync created it), it is
  # returned as-is instead of erroring or duplicating. Everything is account-scoped
  # so different accounts can never collide.
  def create_custom_field
    key = normalized_field_key(params[:name])
    return render(json: { error: 'Clave inválida' }, status: :unprocessable_entity) if key.blank?

    render json: upsert_custom_field(key)
  rescue ActiveRecord::RecordNotUnique
    winner = leads_custom_table.jabvox_custom_columns.find_by(name_jabvox: key)
    return render(json: custom_field_json(winner)) if winner

    render json: { error: 'No se pudo crear el campo' }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  # POST /sources/:id/sync — runs the sync in the background.
  def sync
    return render(json: { error: 'Configura tabla y mapeo antes de sincronizar' }, status: :unprocessable_entity) \
      if @source.table_jabvox.blank? || @source.external_id_column_jabvox.blank? || @source.field_mapping_jabvox.blank?

    # Bloquea solo si hay un sync REALMENTE en curso; un 'syncing' obsoleto no bloquea.
    en_curso = @source.status_jabvox == 'syncing' && @source.updated_at > SYNC_STALE_AFTER.ago
    return render(json: { status: 'syncing', note: 'ya_en_curso' }) if en_curso

    @source.update!(status_jabvox: 'syncing')
    Jabvox::LeadImport::SyncJob.perform_later(@source.id)
    render json: { status: 'syncing' }
  end

  # GET /sources/:id/sync_status — polled for progress/last result.
  def sync_status
    render json: {
      status: @source.status_jabvox,
      last_synced_at: @source.last_synced_at_jabvox,
      last_result: @source.last_sync_result_jabvox
    }
  end

  private

  # Log the real driver error server-side; return a generic message so the
  # frontend never sees host/port/credentials embedded in DB error strings.
  def sanitized(error)
    Rails.logger.error "[LeadImport::Sources] #{error.class}: #{error.message}"
    'No se pudo completar la operación contra la base de datos externa'
  end

  def scoped
    Current.account.jabvox_lead_sources
  end

  def set_source
    @source = scoped.find(params[:id])
  end

  def leads_custom_table
    Current.account.jabvox_custom_tables.find_or_create_by!(linked_to_jabvox: 'leads') do |t|
      t.name_jabvox = 'Leads'
    end
  end

  # Slug seguro para la clave del custom field (evita inyectar claves basura en el JSON).
  def normalized_field_key(raw)
    raw.to_s.downcase.gsub(/[^a-z0-9_]/, '_').squeeze('_').gsub(/\A_|_\z/, '')
  end

  # Crea el custom field o devuelve el existente (idempotente, account-scoped).
  def upsert_custom_field(key)
    type = params[:column_type].to_s
    type = 'text' unless JabvoxCustomColumn::COLUMN_TYPES.include?(type)
    table = leads_custom_table
    existing = table.jabvox_custom_columns.find_by(name_jabvox: key)
    return custom_field_json(existing) if existing

    column = table.jabvox_custom_columns.create!(
      name_jabvox: key, label_jabvox: params.require(:label),
      column_type_jabvox: type, position_jabvox: table.jabvox_custom_columns.count
    )
    custom_field_json(column)
  end

  def custom_field_json(column)
    { key: column.name_jabvox, label: column.label_jabvox,
      column_type: column.column_type_jabvox }
  end

  # All contact fields available for mapping (a lead is backed by a Contact).
  # `kind` tells the sync where to write each one:
  #   contact column, additional_attributes key, or a social_profiles entry.
  STANDARD_LEAD_FIELDS = [
    { key: 'name', label: 'Nombre', kind: 'name' },
    { key: 'last_name', label: 'Apellido', kind: 'last_name' },
    { key: 'email', label: 'Correo electrónico', kind: 'email' },
    { key: 'phone', label: 'Teléfono', kind: 'phone' },
    { key: 'city', label: 'Ciudad', kind: 'attr:city' },
    { key: 'country_code', label: 'País (código ISO)', kind: 'attr:country_code' },
    { key: 'company_name', label: 'Empresa', kind: 'attr:company_name' },
    { key: 'identification_number', label: 'Documento / Identificación', kind: 'attr:jabvox_identification_number' },
    { key: 'description', label: 'Biografía', kind: 'attr:description' },
    { key: 'linkedin', label: 'LinkedIn', kind: 'social:linkedin' },
    { key: 'facebook', label: 'Facebook', kind: 'social:facebook' },
    { key: 'instagram', label: 'Instagram', kind: 'social:instagram' },
    { key: 'twitter', label: 'Twitter/X', kind: 'social:twitter' },
    { key: 'telegram', label: 'Telegram', kind: 'social:telegram' },
    { key: 'tiktok', label: 'TikTok', kind: 'social:tiktok' },
    { key: 'github', label: 'Github', kind: 'social:github' }
  ].freeze

  def standard_lead_fields
    STANDARD_LEAD_FIELDS
  end

  def custom_lead_fields
    table = Current.account.jabvox_custom_tables.find_by(linked_to_jabvox: 'leads')
    return [] unless table

    table.jabvox_custom_columns.ordered.map do |c|
      { key: c.name_jabvox, label: c.label_jabvox, kind: 'custom', column_type: c.column_type_jabvox }
    end
  end

  def blank_password_key
    params.dig(:source, :password_jabvox).blank? ? [:password_jabvox] : []
  end

  def source_params
    params.require(:source).permit(
      :name_jabvox, :engine_jabvox, :host_jabvox, :port_jabvox, :database_jabvox,
      :username_jabvox, :password_jabvox, :ssl_mode_jabvox, :allow_private_network_jabvox,
      :query_timeout_ms_jabvox, :table_jabvox, :external_id_column_jabvox,
      :phone_prefix_jabvox, :country_jabvox,
      field_mapping_jabvox: {},
      related_tables_jabvox: [%i[table local_key foreign_key alias]],
      filters_jabvox: [%i[column op value value2]]
    )
  end

  # NEVER exposes the password. Only whether one is set.
  # Mapeo plano de columnas a JSON; largo por el nº de campos, no por complejidad.
  # rubocop:disable Metrics/MethodLength
  def serialize(source)
    {
      id: source.id,
      name_jabvox: source.name_jabvox,
      engine_jabvox: source.engine_jabvox,
      host_jabvox: source.host_jabvox,
      port_jabvox: source.port_jabvox,
      database_jabvox: source.database_jabvox,
      username_jabvox: source.username_jabvox,
      ssl_mode_jabvox: source.ssl_mode_jabvox,
      allow_private_network_jabvox: source.allow_private_network_jabvox,
      query_timeout_ms_jabvox: source.query_timeout_ms_jabvox,
      table_jabvox: source.table_jabvox,
      external_id_column_jabvox: source.external_id_column_jabvox,
      field_mapping_jabvox: source.field_mapping_jabvox,
      related_tables_jabvox: source.related_tables_jabvox,
      filters_jabvox: source.filters_jabvox,
      phone_prefix_jabvox: source.phone_prefix_jabvox,
      country_jabvox: source.country_jabvox,
      status_jabvox: source.status_jabvox,
      last_tested_at_jabvox: source.last_tested_at_jabvox,
      last_synced_at_jabvox: source.last_synced_at_jabvox,
      last_sync_result_jabvox: source.last_sync_result_jabvox,
      has_password: source.password_jabvox.present?,
      created_at: source.created_at
    }
  end
  # rubocop:enable Metrics/MethodLength
end
# rubocop:enable Metrics/ClassLength
