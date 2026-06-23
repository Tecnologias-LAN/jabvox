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

  # Real, account-scoped KPI counters for the Analytics Overview/Home. Only
  # counts entities that actually exist — no fabricated metrics.
  def overview_stats
    render json: overview_counters(Current.account)
  end

  # Catalog of built-in internal reports the user can turn into dashboards.
  def internal_reports
    render json: Jabvox::Analytics::InternalReportCatalog.all
  end

  # Create one dashboard per selected internal report (keys[]). Each dashboard
  # gets a single widget bound to that report (config.report_key). Idempotent
  # by dashboard name. Account-scoped end to end.
  def create_internal_reports
    authorize!(:create)
    keys = Array(params[:keys]).map(&:to_s).select { |k| Jabvox::Analytics::InternalReportCatalog.exists?(k) }
    created = Jabvox::Analytics::InternalReportSeeder.new(
      account: Current.account, user: current_user, keys: keys
    ).call
    audit!(action: 'dashboard.create_internal_reports', auditable: created.first)
    render json: created.compact.map { |d| serialize(d) }, status: :created
  end

  # Create the two predefined dashboards (Autogestión + Valiosas) and link them
  # to the external data sources named CRM_Autogestion / CRM_Valiosas if present.
  # Idempotent: existing dashboards with those names are left untouched.
  def seed_defaults
    authorize!(:create)
    dashboards = Jabvox::Analytics::DefaultDashboardSeeder.new(
      account: Current.account,
      user: current_user
    ).call
    audit!(action: 'dashboard.seed_defaults', auditable: dashboards.first)
    render json: dashboards.compact.map { |d| serialize(d) }, status: :created
  end

  private

  def overview_counters(acc)
    sources = acc.jabvox_analytics_data_sources
    {
      total_dashboards: acc.jabvox_analytics_dashboards.count,
      total_data_sources: sources.count,
      data_sources_ok: sources.where(status_jabvox: 'ok').count,
      total_widgets: JabvoxAnalyticsDashboardWidget.where(account_id: acc.id).count,
      total_folders: acc.jabvox_analytics_folders.count
    }.merge(overview_access_counters(acc))
  end

  def overview_access_counters(acc)
    {
      shared_dashboards: JabvoxAnalyticsShare.where(account_id: acc.id).distinct.count(:dashboard_id),
      users_with_access: JabvoxAnalyticsUserPermission.where(account_id: acc.id).distinct.count(:user_id),
      actions_today: acc.jabvox_analytics_audit_logs.where(created_at: Time.zone.today.all_day).count,
      total_exports: acc.jabvox_analytics_exports.count
    }
  end

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
