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
    return render json: { error: 'El widget no tiene fuente de datos' }, status: :unprocessable_entity unless @widget.data_source

    unless permission_resolver.can_access_data_source?(@widget.data_source)
      return render json: { error: 'Sin acceso a la fuente de datos del widget' }, status: :forbidden
    end

    svc = Jabvox::Analytics::QueryExecutionService.new(
      data_source: @widget.data_source, user: current_user, ttl_seconds: @dashboard.cache_ttl_seconds_jabvox
    )
    outcome = if @widget.uses_custom_sql?
                svc.run_custom_sql(@widget.custom_sql_jabvox)
              else
                svc.run_visual(merged_spec)
              end
    render json: outcome.to_h
  rescue Jabvox::Analytics::QueryExecutionService::RejectedError, Jabvox::Analytics::QueryBuilderService::InvalidSpec => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "[Analytics::Widget] execute failed: #{e.message}"
    render json: { error: 'No se pudo ejecutar el widget' }, status: :unprocessable_entity
  end

  private

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
