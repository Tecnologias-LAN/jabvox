class Api::V1::Accounts::Jabvox::Analytics::DataSourcesController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :set_data_source,
                only: %i[show update destroy test_connection schema preview column_values query compile_sql custom_sql validate_sql sync]
  before_action :authorize_manage!, only: %i[create update destroy]
  before_action :authorize_data_source_access!, only: %i[schema preview column_values query compile_sql]
  before_action :authorize_custom_sql!, only: %i[custom_sql]

  def index
    sources = scoped_sources.order(:name_jabvox)
    render json: sources.map { |s| serialize(s) }
  end

  def show
    render json: serialize(@data_source)
  end

  def create
    source = scoped_sources.new(data_source_params)
    source.account = Current.account
    source.created_by = current_user
    if source.save
      audit!(action: 'data_source.create', auditable: source, metadata: { engine: source.engine_jabvox })
      grant_default_permission(source)
      render json: serialize(source), status: :created
    else
      render json: { errors: source.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @data_source.update(data_source_params)
      audit!(action: 'data_source.update', auditable: @data_source)
      render json: serialize(@data_source)
    else
      render json: { errors: @data_source.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @data_source.destroy!
    audit!(action: 'data_source.delete', auditable: @data_source)
    head :no_content
  end

  # Test an already-saved source.
  def test_connection
    result = Jabvox::Analytics::ConnectionTestService.new(@data_source).call
    audit!(action: 'connection.test', result: result[:success] ? 'success' : 'failure',
           auditable: @data_source, metadata: { latency_ms: result[:latency_ms] })
    render json: result
  end

  # Test connection parameters before saving (collection route).
  def test_connection_unsaved
    source = Current.account.jabvox_analytics_data_sources.new(data_source_params)
    result = Jabvox::Analytics::ConnectionTestService.new(source).call
    audit!(action: 'connection.test', result: result[:success] ? 'success' : 'failure',
           metadata: { engine: source.engine_jabvox, latency_ms: result[:latency_ms] })
    render json: result
  end

  def schema
    schema = Jabvox::Analytics::IntrospectionService.new(@data_source).call
    render json: { schema: schema }
  rescue StandardError => e
    ds_error(e)
  end

  def preview
    outcome = execution_service.preview(
      table: params.require(:table), page: params[:page] || 1, per_page: params[:per_page] || 100,
      sort: params[:sort], search: params[:search], filters: params[:filters]&.to_unsafe_h
    )
    audit!(action: 'data.preview', auditable: @data_source, metadata: { table: params[:table] })
    render json: outcome.to_h
  rescue StandardError => e
    ds_error(e)
  end

  # Valores distintos de una columna para los filtros seleccionables del visor de datos.
  def column_values
    result = execution_service.distinct_values(
      table: params.require(:table), column: params.require(:column),
      search: params[:search], limit: params[:limit] || 200
    )
    render json: result
  rescue StandardError => e
    ds_error(e)
  end

  # Compila el spec visual a SQL (sin ejecutar), para la conversión visual→SQL del editor.
  def compile_sql
    spec = params.require(:query_spec).permit!.to_h
    render json: { sql: execution_service.compile_sql(spec) }
  rescue Jabvox::Analytics::QueryBuilderService::InvalidSpec => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def query
    spec = params.require(:query_spec).permit!.to_h
    outcome = execution_service.run_visual(spec)
    audit!(action: 'query.execute', auditable: @data_source, metadata: { row_count: outcome.row_count })
    render json: outcome.to_h
  rescue Jabvox::Analytics::QueryBuilderService::InvalidSpec => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    ds_error(e)
  end

  def validate_sql
    result = Jabvox::Analytics::SqlValidatorService.new(params[:sql]).call
    render json: { valid: result.valid?, message: result.message }
  end

  def custom_sql
    outcome = execution_service.run_custom_sql(params.require(:sql))
    audit!(action: 'custom_sql.execute', auditable: @data_source,
           metadata: { sql: params[:sql], row_count: outcome.row_count })
    render json: outcome.to_h
  rescue Jabvox::Analytics::QueryExecutionService::RejectedError => e
    audit!(action: 'custom_sql.execute', result: 'rejected', auditable: @data_source,
           metadata: { sql: params[:sql], reason: e.message })
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    ds_error(e)
  end

  def sync
    schema = Jabvox::Analytics::IntrospectionService.new(@data_source).call(refresh: true)
    Jabvox::Analytics::ConnectionTestService.new(@data_source).call
    render json: { schema: schema }
  rescue StandardError => e
    ds_error(e)
  end

  private

  def scoped_sources
    Current.account.jabvox_analytics_data_sources
  end

  def set_data_source
    @data_source = scoped_sources.find(params[:id])
  end

  def execution_service
    Jabvox::Analytics::QueryExecutionService.new(data_source: @data_source, user: current_user)
  end

  def authorize_manage!
    authorize!(:manage_data_sources)
  end

  def authorize_data_source_access!
    return if permission_resolver.can_access_data_source?(@data_source)

    render json: { error: 'No tienes acceso a esta fuente de datos' }, status: :forbidden
  end

  def authorize_custom_sql!
    return if permission_resolver.can_use_custom_sql_on?(@data_source)

    render json: { error: 'No estás autorizado para ejecutar SQL personalizado' }, status: :forbidden
  end

  # Grant the creator (and admins implicitly) query + custom SQL access to a new source.
  def grant_default_permission(source)
    JabvoxAnalyticsDataSourcePermission.find_or_create_by!(
      account: Current.account, data_source: source, user: current_user
    ) do |p|
      p.can_query_jabvox = true
      p.can_use_custom_sql_jabvox = true
    end
  end

  def data_source_params
    params.require(:data_source).permit(
      :name_jabvox, :engine_jabvox, :host_jabvox, :port_jabvox, :database_jabvox,
      :username_jabvox, :password_jabvox, :ssl_mode_jabvox, :ssl_ca_jabvox, :sqlite_path_jabvox,
      :allow_private_network_jabvox, :max_rows_jabvox, :query_timeout_ms_jabvox, options_jabvox: {}
    ).tap do |p|
      # On update, drop a blank password so the existing encrypted value is kept.
      p.delete(:password_jabvox) if action_name == 'update' && p[:password_jabvox].blank?
    end
  end

  # Public, secret-free representation. NEVER includes password/ssl_ca.
  # Representación pública, sin secretos. NUNCA incluye password/ssl_ca.
  SERIALIZED_ATTRS = %i[
    id name_jabvox engine_jabvox host_jabvox port_jabvox database_jabvox username_jabvox
    sqlite_path_jabvox ssl_mode_jabvox allow_private_network_jabvox max_rows_jabvox
    query_timeout_ms_jabvox status_jabvox last_tested_at_jabvox created_at
  ].freeze

  def serialize(source)
    source.slice(*SERIALIZED_ATTRS).symbolize_keys.merge(
      has_password: source.password_jabvox.present?
    )
  end

  def sanitized(error)
    Rails.logger.error "[Analytics::DataSources] #{error.class}: #{error.message}"
    'No se pudo completar la operación contra la fuente de datos'
  end

  def ds_error(error)
    render json: { error: sanitized(error) }, status: :unprocessable_entity
  end
end
