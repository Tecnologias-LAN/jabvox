class Api::V1::Accounts::Jabvox::Analytics::DashboardsController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :set_dashboard, only: %i[show update destroy layout duplicate]
  before_action :ensure_can_view!, only: %i[show]
  before_action :ensure_can_edit!, only: %i[update destroy layout]

  def index
    dashboards = permission_resolver.scope_for(scoped).order(:name_jabvox)
    render json: dashboards.map { |d| serialize(d) }
  end

  def show
    render json: serialize(@dashboard, detailed: true)
  end

  def create
    authorize!(:create)
    dashboard = scoped.new(dashboard_params)
    dashboard.account = Current.account
    dashboard.created_by = current_user
    if dashboard.save
      audit!(action: 'dashboard.create', auditable: dashboard)
      render json: serialize(dashboard), status: :created
    else
      render json: { errors: dashboard.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @dashboard.update(dashboard_params)
      audit!(action: 'dashboard.update', auditable: @dashboard)
      render json: serialize(@dashboard)
    else
      render json: { errors: @dashboard.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @dashboard.destroy!
    audit!(action: 'dashboard.delete', auditable: @dashboard)
    head :no_content
  end

  # Persist the grid layout (per-breakpoint x/y/w/h). Autosaved from the builder.
  def layout
    @dashboard.update!(layout_jabvox: params.require(:layout))
    head :no_content
  end

  def duplicate
    authorize!(:create)
    copy = @dashboard.dup
    copy.name_jabvox = "#{@dashboard.name_jabvox} (copia)"
    copy.created_by = current_user
    copy.save!
    @dashboard.widgets.find_each do |w|
      copy.widgets.create!(w.attributes.except('id', 'dashboard_id', 'created_at', 'updated_at').merge('account_id' => Current.account.id))
    end
    audit!(action: 'dashboard.duplicate', auditable: copy)
    render json: serialize(copy), status: :created
  end

  private

  def scoped
    Current.account.jabvox_analytics_dashboards
  end

  def set_dashboard
    @dashboard = scoped.find(params[:id])
  end

  def share_service
    @share_service ||= Jabvox::Analytics::ShareService.new(@dashboard, current_user, Current.account)
  end

  def ensure_can_view!
    return if share_service.can_view? || permission_resolver.view_all_data?

    render json: { error: 'No tienes acceso a este dashboard' }, status: :forbidden
  end

  def ensure_can_edit!
    return if share_service.can_edit?

    render json: { error: 'No puedes editar este dashboard' }, status: :forbidden
  end

  def dashboard_params
    params.require(:dashboard).permit(
      :name_jabvox, :description_jabvox, :folder_id, :cache_ttl_seconds_jabvox, :is_template_jabvox,
      layout_jabvox: {}, global_filters_jabvox: {}
    )
  end

  def serialize(dashboard, detailed: false)
    base = {
      id: dashboard.id,
      name_jabvox: dashboard.name_jabvox,
      description_jabvox: dashboard.description_jabvox,
      folder_id: dashboard.folder_id,
      cache_ttl_seconds_jabvox: dashboard.cache_ttl_seconds_jabvox,
      is_template_jabvox: dashboard.is_template_jabvox,
      created_by_id: dashboard.created_by_id,
      created_at: dashboard.created_at
    }
    return base unless detailed

    base.merge(
      layout_jabvox: dashboard.layout_jabvox,
      global_filters_jabvox: dashboard.global_filters_jabvox,
      access_level: Jabvox::Analytics::ShareService.new(dashboard, current_user, Current.account).access_level
    )
  end
end
