class Api::V1::Accounts::Jabvox::DataExport::TargetsController < Api::V1::Accounts::Jabvox::DataExport::BaseController
  before_action :set_target,
                only: %i[show update destroy test_connection build_schema toggle
                         remote_schema mapping sync_now]

  # One export DB per account, but modeled as a collection for consistency.
  def index
    render json: { targets: scoped.order(:name_jabvox).map { |x| serialize(x) } }
  end

  def show
    render json: serialize(@target)
  end

  def create
    target = scoped.new(target_params)
    target.created_by = current_user
    target.save!
    render json: serialize(target), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @target.update!(target_params.except(*blank_password_key))
    Jabvox::ExternalExport.bust_cache(Current.account.id)
    render json: serialize(@target)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    # Only stops exporting; never touches the external DB (its data stays).
    @target.destroy!
    Jabvox::ExternalExport.bust_cache(Current.account.id)
    head :no_content
  end

  # POST /targets/test_connection — unsaved params.
  def test_connection_unsaved
    target = scoped.new(target_params)
    render json: Jabvox::ExternalExport::WriteAdapter.new(target).test_connection
  end

  # POST /targets/:id/test_connection — saved target.
  def test_connection
    result = Jabvox::ExternalExport::WriteAdapter.new(@target).test_connection
    @target.update!(status_jabvox: result[:success] ? 'ok' : 'error', last_tested_at_jabvox: Time.current)
    render json: result
  end

  # POST /targets/:id/build_schema — creates/updates the mirror tables.
  def build_schema
    Jabvox::ExternalExport::SchemaBuilderService.new(@target).call
    render json: { built_at: @target.reload.schema_built_at_jabvox }
  rescue StandardError => e
    render json: { error: sanitized(e) }, status: :unprocessable_entity
  end

  # POST /targets/:id/toggle — enable/disable real-time export. Enabling also
  # kicks off a full backfill so historical data lands in the external DB.
  def toggle
    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    @target.update!(enabled_jabvox: enabled)
    Jabvox::ExternalExport.bust_cache(Current.account.id)
    Jabvox::ExternalExport::BackfillJob.perform_later(Current.account.id, incremental: false) if enabled
    render json: serialize(@target)
  end

  # GET /targets/:id/remote_schema — tables + columns that already exist in the
  # customer's DB (map mode), plus the jabvox tables/columns available to map FROM.
  def remote_schema
    remote = introspect_remote
    render json: {
      remote_tables: remote,
      jabvox_tables: jabvox_catalog
    }
  rescue StandardError => e
    render json: { error: sanitized(e) }, status: :unprocessable_entity
  end

  # POST /targets/:id/mapping — saves mode + field mapping (+ optional DDL flag).
  def mapping
    @target.update!(mapping_params)
    Jabvox::ExternalExport.bust_cache(Current.account.id)
    render json: serialize(@target)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  # POST /targets/:id/sync_now — enqueue a manual full backfill.
  def sync_now
    Jabvox::ExternalExport::BackfillJob.perform_later(Current.account.id, incremental: false)
    render json: { queued: true }
  end

  private

  # [{ name:, columns: [{ name:, type: }] }] for the customer's existing tables.
  def introspect_remote
    Jabvox::Analytics::AdapterFactory.for(@target).schema_introspection.map do |rel|
      { name: rel[:name],
        columns: Array(rel[:columns]).map { |c| { name: c[:name], type: c[:type] } } }
    end
  end

  # The jabvox tables and their SAFE columns (what can be mapped FROM). This is
  # the same whitelist the exporter uses, so the UI can never offer a sensitive
  # column.
  def jabvox_catalog
    Jabvox::ExternalExport::Catalog.exportable_models.map do |model|
      { table: Jabvox::ExternalExport::Catalog.table_name_for(model),
        columns: Jabvox::ExternalExport::Catalog.safe_columns(model) }
    end
  end

  def scoped
    Current.account.jabvox_export_targets
  end

  def set_target
    @target = scoped.find(params[:id])
  end

  def sanitized(error)
    Rails.logger.error("[DataExport::Targets] #{error.class}: #{error.message}")
    'No se pudo completar la operación contra la base de datos externa'
  end

  def blank_password_key
    params.dig(:target, :password_jabvox).blank? ? [:password_jabvox] : []
  end

  def target_params
    params.require(:target).permit(
      :name_jabvox, :engine_jabvox, :host_jabvox, :port_jabvox, :database_jabvox,
      :username_jabvox, :password_jabvox, :ssl_mode_jabvox, :allow_private_network_jabvox,
      :query_timeout_ms_jabvox, :mode_jabvox
    )
  end

  # field_mapping is a free-form nested hash { table => { key:, columns: {...} } };
  # it's validated against the model's safe columns and the remote schema at write
  # time (RowExporterService only writes whitelisted columns), so permit! is safe.
  def mapping_params
    params.require(:target).permit(:mode_jabvox, :create_missing_columns_jabvox).tap do |p|
      raw = params[:target][:field_mapping_jabvox]
      p[:field_mapping_jabvox] = raw.respond_to?(:permit!) ? raw.permit!.to_h : (raw || {})
    end
  end

  # NEVER exposes the password.
  def serialize(target)
    {
      id: target.id,
      name_jabvox: target.name_jabvox,
      engine_jabvox: target.engine_jabvox,
      host_jabvox: target.host_jabvox,
      port_jabvox: target.port_jabvox,
      database_jabvox: target.database_jabvox,
      username_jabvox: target.username_jabvox,
      ssl_mode_jabvox: target.ssl_mode_jabvox,
      allow_private_network_jabvox: target.allow_private_network_jabvox,
      query_timeout_ms_jabvox: target.query_timeout_ms_jabvox,
      enabled_jabvox: target.enabled_jabvox,
      status_jabvox: target.status_jabvox,
      mode_jabvox: target.mode_jabvox,
      field_mapping_jabvox: target.field_mapping_jabvox,
      create_missing_columns_jabvox: target.create_missing_columns_jabvox,
      sync_status_jabvox: target.sync_status_jabvox,
      last_full_sync_at_jabvox: target.last_full_sync_at_jabvox,
      last_sync_result_jabvox: target.last_sync_result_jabvox,
      schema_built_at_jabvox: target.schema_built_at_jabvox,
      last_tested_at_jabvox: target.last_tested_at_jabvox,
      last_export_at_jabvox: target.last_export_at_jabvox,
      last_error_jabvox: target.last_error_jabvox,
      has_password: target.password_jabvox.present?,
      created_at: target.created_at
    }
  end
end
