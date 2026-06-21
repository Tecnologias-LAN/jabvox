class Api::V1::Accounts::Jabvox::Analytics::ExportsController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :set_export, only: %i[show destroy]

  def index
    render json: scoped.recent.limit(50).map { |e| serialize(e) }
  end

  def show
    render json: serialize(@export)
  end

  def create
    authorize!(:export)
    dashboard = Current.account.jabvox_analytics_dashboards.find(export_params[:dashboard_id])
    unless Jabvox::Analytics::ShareService.new(dashboard, current_user, Current.account).can_view?
      return render json: { error: 'No tienes acceso a este dashboard' }, status: :forbidden
    end

    export = scoped.create!(
      dashboard: dashboard, user: current_user,
      format_jabvox: export_params[:format_jabvox], params_jabvox: export_params[:params_jabvox] || {}
    )
    Jabvox::Analytics::ExportJob.perform_later(export.id)
    audit!(action: 'export.create', auditable: dashboard, metadata: { format: export.format_jabvox })
    render json: serialize(export), status: :accepted
  end

  def destroy
    @export.destroy!
    head :no_content
  end

  private

  def scoped
    Current.account.jabvox_analytics_exports
  end

  def set_export
    @export = scoped.find(params[:id])
  end

  def export_params
    params.require(:export).permit(:dashboard_id, :format_jabvox, params_jabvox: {})
  end

  def serialize(export)
    {
      id: export.id,
      dashboard_id: export.dashboard_id,
      format_jabvox: export.format_jabvox,
      status_jabvox: export.status_jabvox,
      file_url_jabvox: export.file_url_jabvox,
      error_jabvox: export.error_jabvox,
      created_at: export.created_at
    }
  end
end
