# Read-only access to the Analytics audit trail. Admins and supervisors only.
class Api::V1::Accounts::Jabvox::Analytics::AuditLogsController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :ensure_can_view_audit

  PER_PAGE = 50

  def index
    logs = filtered_logs
    page = [params[:page].to_i, 1].max
    total = logs.count
    records = logs.offset((page - 1) * PER_PAGE).limit(PER_PAGE)
    render json: { payload: records.map { |l| serialize(l) }, meta: { total: total, page: page, per_page: PER_PAGE } }
  end

  def show
    render json: serialize(scoped.find(params[:id]))
  end

  private

  def scoped
    Current.account.jabvox_analytics_audit_logs.includes(:user)
  end

  def filtered_logs
    logs = scoped.recent
    logs = logs.for_action(params[:action_filter]) if params[:action_filter].present?
    logs = logs.where(result_jabvox: params[:result]) if params[:result].present?
    logs
  end

  def ensure_can_view_audit
    return if Current.account_user&.administrator?
    return if permission_resolver.can?(:view_all_data)

    render json: { error: 'No tienes permiso para ver la auditoría' }, status: :forbidden
  end

  def serialize(log)
    {
      id: log.id,
      user: log.user&.name,
      user_id: log.user_id,
      action_jabvox: log.action_jabvox,
      result_jabvox: log.result_jabvox,
      auditable_type_jabvox: log.auditable_type_jabvox,
      auditable_id_jabvox: log.auditable_id_jabvox,
      ip_address_jabvox: log.ip_address_jabvox,
      metadata_jabvox: log.metadata_jabvox,
      created_at: log.created_at
    }
  end
end
