class Api::V1::Accounts::Jabvox::Analytics::DashboardWidgetsController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :set_dashboard
  before_action :set_widget, only: %i[show update destroy execute]
  before_action :ensure_can_edit!, only: %i[create update destroy]

  def index
    render json: @dashboard.widgets.ordered.map { |w| serialize(w) }
  end

  def show
    render json: serialize(@widget)
  end

  def create
    widget = @dashboard.widgets.new(widget_params)
    widget.account = Current.account
    if widget.save
      render json: serialize(widget), status: :created
    else
      render json: { errors: widget.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @widget.update(widget_params)
      render json: serialize(@widget)
    else
      render json: { errors: @widget.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @widget.destroy!
    head :no_content
  end

  # Run this widget's query (visual spec or custom SQL) against its data source, cached.
  def execute
    config = @widget.config_jabvox.is_a?(Hash) ? @widget.config_jabvox : {}
    # Internal report widgets resolve to a pre-baked Ruby service scoped to the
    # current account — no data source, no raw SQL, no cross-account access.
    return execute_internal_report(config['report_key']) if config['report_key'].present?
    # Cross-source report widgets run a saved cross report (join across sources).
    return execute_cross_report(config['cross_report_id']) if config['cross_report_id'].present?

    execute_data_source_widget
  rescue Jabvox::Analytics::QueryExecutionService::RejectedError, Jabvox::Analytics::QueryBuilderService::InvalidSpec => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "[Analytics::Widget] execute failed: #{e.message}"
    render json: { error: 'No se pudo ejecutar el widget' }, status: :unprocessable_entity
  end

  # Runs a widget backed by a saved cross-source report. The report is looked up
  # scoped to the current account (tenant isolation) and executed by the cross
  # engine, returning the same { columns, rows } shape widgets already render.
  def execute_cross_report(cross_report_id)
    report = JabvoxAnalyticsCrossReport.find_by(id: cross_report_id, account_id: Current.account.id)
    return render json: { error: 'El reporte cruzado no existe' }, status: :not_found unless report

    result = Jabvox::Analytics::CrossReportExecutionService.new(report).call
    render json: { columns: result.columns, rows: result.rows, row_count: result.row_count }
  rescue Jabvox::Analytics::CrossReportExecutionService::ExecutionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Runs a widget backed by an external/SQL data source (visual spec or custom SQL).
  def execute_data_source_widget
    return render json: { error: 'El widget no tiene fuente de datos' }, status: :unprocessable_entity unless @widget.data_source

    unless permission_resolver.can_access_data_source?(@widget.data_source)
      return render json: { error: 'Sin acceso a la fuente de datos del widget' }, status: :forbidden
    end

    svc = Jabvox::Analytics::QueryExecutionService.new(
      data_source: @widget.data_source, user: current_user, ttl_seconds: @dashboard.cache_ttl_seconds_jabvox
    )
    outcome = @widget.uses_custom_sql? ? svc.run_custom_sql(@widget.custom_sql_jabvox) : svc.run_visual(merged_spec)
    render json: outcome.to_h
  end

  private

  # Executes a built-in report. The service is always instantiated with
  # Current.account, so the account_id filter is applied through ActiveRecord
  # and cannot be bypassed by any input.
  def execute_internal_report(report_key)
    unless Jabvox::Analytics::InternalReportCatalog.exists?(report_key)
      return render json: { error: 'Reporte interno desconocido' }, status: :unprocessable_entity
    end

    service = Jabvox::Analytics::InternalReportCatalog.service_for(report_key)
    return render json: { error: 'Reporte interno no implementado' }, status: :unprocessable_entity unless service

    cfg = @widget.config_jabvox
    filters = effective_filters(cfg)
    data = service.new(account: Current.account, **service_filter_args(filters)).call.deep_symbolize_keys
    render json: section_to_render(data, cfg['section'], cfg['metric'])
  rescue StandardError => e
    Rails.logger.error "[Analytics::InternalReport] #{report_key} failed: #{e.message}"
    render json: { error: 'No se pudo ejecutar el reporte interno' }, status: :unprocessable_entity
  end

  # Widget-level filters + the dashboard's global filters (date range +
  # dynamic field filters, flattened so services read them directly).
  def effective_filters(cfg)
    filters = cfg['filters'].is_a?(Hash) ? cfg['filters'].dup : {}
    return filters unless params[:global_filters].respond_to?(:to_unsafe_h)

    gf = params[:global_filters].to_unsafe_h.stringify_keys
    dynamic = gf.delete('dynamic')
    filters.merge!(gf)
    filters.merge!(dynamic.stringify_keys) if dynamic.is_a?(Hash)
    filters
  end

  # Only forward filter keys the service constructor understands. All services
  # accept date_from/date_to; richer filters are accepted as a `filters` hash.
  def service_filter_args(filters)
    {
      date_from: filters['date_from'] || filters[:date_from],
      date_to: filters['date_to'] || filters[:date_to],
      filters: filters
    }
  end

  # Render one section of a report in the shape its widget type needs:
  #   - metric set  -> { rows: [[value]] } so KpiCardWidget shows a single number
  #   - summary      -> Métrica | Valor table
  #   - array (by_*) -> { columns:, rows: } table / bar (renderer reads both)
  #   - series       -> { columns:, rows: } with date first (line/bar)
  def section_to_render(data, section, metric)
    return single_metric(data, metric) if metric.present?

    part = section.present? ? data[section.to_sym] : nil
    return hash_to_table(part) if part.is_a?(Hash)
    return array_to_table(part) if part.is_a?(Array)

    report_to_table(data)
  end

  def single_metric(data, metric)
    { columns: [humanize_key(metric)], rows: [[format_value(data.dig(:summary, metric.to_sym))]] }
  end

  def hash_to_table(hash)
    { columns: %w[Métrica Valor], rows: hash.map { |k, v| [humanize_key(k), format_value(v)] } }
  end

  def array_to_table(arr)
    return { columns: [], rows: [] } if arr.empty?

    cols = arr.first.keys.map { |k| humanize_key(k) }
    { columns: cols, rows: arr.map { |h| h.values.map { |v| format_value(v) } } }
  end

  def report_to_table(data)
    return hash_to_table(data[:summary]) if data[:summary].is_a?(Hash) && data[:summary].any?

    array_to_table(data.values.find { |v| v.is_a?(Array) && v.first.is_a?(Hash) } || [])
  end

  def humanize_key(key)
    key.to_s.tr('_', ' ').strip.capitalize
  end

  def format_value(value)
    case value
    when Float then value.round(2)
    when Hash then value[:available] == false ? 'N/D' : value.to_s
    else value
    end
  end

  def set_dashboard
    @dashboard = Current.account.jabvox_analytics_dashboards.find(params[:dashboard_id])
  end

  def set_widget
    @widget = @dashboard.widgets.find(params[:id])
  end

  def ensure_can_edit!
    return if Jabvox::Analytics::ShareService.new(@dashboard, current_user, Current.account).can_edit?

    render json: { error: 'No puedes editar este dashboard' }, status: :forbidden
  end

  # Apply incoming global filters to the stored query spec (filters appended).
  def merged_spec
    spec = (@widget.query_spec_jabvox || {}).deep_dup
    global = params[:global_filters]
    return spec if global.blank?

    spec['filters'] = Array(spec['filters']) + Array(global.permit!.to_h['filters'])
    spec
  end

  def widget_params
    params.require(:widget).permit(
      :widget_type_jabvox, :title_jabvox, :data_source_id, :custom_sql_jabvox, :position_jabvox,
      query_spec_jabvox: {}, config_jabvox: {}
    )
  end

  def serialize(widget)
    {
      id: widget.id,
      dashboard_id: widget.dashboard_id,
      data_source_id: widget.data_source_id,
      widget_type_jabvox: widget.widget_type_jabvox,
      title_jabvox: widget.title_jabvox,
      query_spec_jabvox: widget.query_spec_jabvox,
      custom_sql_jabvox: widget.custom_sql_jabvox,
      config_jabvox: widget.config_jabvox,
      position_jabvox: widget.position_jabvox
    }
  end
end
