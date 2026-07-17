class Api::V1::Accounts::Jabvox::DataExport::TargetsController < Api::V1::Accounts::Jabvox::DataExport::BaseController
  before_action :set_target,
                only: %i[show update destroy test_connection build_schema toggle
                         sync_now history]

  # One export DB per account, but modeled as a collection for consistency.
  def index
    render json: { targets: scoped.order(:name_jabvox).map { |x| serialize(x) } }
  end

  def show
    render json: serialize(@target)
  end

  # Export groups available to this account (for the settings UI checklist).
  def available_groups
    render json: { groups: Jabvox::ExternalExport::Catalog.available_groups(Current.account) }
  end

  def create
    # Golden rule: exactly one external DB per account.
    if scoped.exists?
      return render json: { error: 'Ya existe una base de datos externa para esta cuenta' },
                    status: :unprocessable_entity
    end

    target = scoped.new(target_params)
    target.created_by = current_user
    target.save!
    render json: serialize(target), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    # Concurrent create raced past the check — the unique index is the backstop.
    render json: { error: 'Ya existe una base de datos externa para esta cuenta' },
           status: :unprocessable_entity
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

  # POST /targets/:id/sync_now — enqueue a manual full backfill.
  def sync_now
    Jabvox::ExternalExport::BackfillJob.perform_later(Current.account.id, incremental: false)
    render json: { queued: true }
  end

  # GET /targets/:id/history — sync history: counts + a paginated list of records,
  # optionally filtered by status (queued | exported | failed).
  def history
    logs = @target.jabvox_export_sync_logs.with_status(params[:status]).recent_first
    page = params[:page].to_i
    page = 1 if page < 1
    per = 25
    total = logs.count
    items = logs.offset((page - 1) * per).limit(per)

    render json: {
      counts: JabvoxExportSyncLog.counts_for(@target),
      page: page,
      total: total,
      items: items.map { |l| serialize_log(l) }
    }
  end

  private

  def serialize_log(log)
    {
      id: log.id,
      model: log.model_name_jabvox,
      record_id: log.record_id_jabvox,
      status: log.status_jabvox,
      operation: log.operation_jabvox,
      error: log.error_jabvox,
      attempts: log.attempts_jabvox,
      last_attempt_at: log.last_attempt_at_jabvox,
      exported_at: log.exported_at_jabvox
    }
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
    permitted = params.require(:target).permit(
      :name_jabvox, :engine_jabvox, :host_jabvox, :port_jabvox, :database_jabvox,
      :username_jabvox, :password_jabvox, :ssl_mode_jabvox, :allow_private_network_jabvox,
      :query_timeout_ms_jabvox, selected_modules_jabvox: []
    )
    # Whitelist selected module keys against the known groups (never trust input).
    if permitted.key?(:selected_modules_jabvox)
      valid = Jabvox::ExternalExport::Catalog::EXPORT_GROUPS.map { |g| g[:key] }
      permitted[:selected_modules_jabvox] = Array(permitted[:selected_modules_jabvox]).map(&:to_s) & valid
    end
    permitted
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
      selected_modules_jabvox: target.selected_modules,
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
