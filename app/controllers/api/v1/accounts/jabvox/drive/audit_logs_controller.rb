class Api::V1::Accounts::Jabvox::Drive::AuditLogsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_drive'

  PER_PAGE = 50

  # Historial de actividad del Drive de la cuenta: quién hizo qué y cuándo.
  # Filtrable por acción, usuario, recurso y fecha. Solo administradores (ver policy).
  def index
    authorize JabvoxDriveAuditLog
    logs = policy_scope(Current.account.jabvox_drive_audit_logs)
    logs = apply_filters(logs).recent
    page = params[:page].to_i
    page = 1 if page < 1
    logs = logs.limit(PER_PAGE).offset((page - 1) * PER_PAGE)
    render json: { payload: logs.map { |l| serialize_log(l) }, meta: { page: page, per_page: PER_PAGE } }
  end

  private

  def apply_filters(scope)
    scope = scope.for_action(params[:action_name]) if params[:action_name].present?
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    scope = scope.for_auditable(params[:auditable_type], params[:auditable_id]) if params[:auditable_type].present? && params[:auditable_id].present?
    scope = scope.where('created_at >= ?', parse_date(params[:created_after])) if params[:created_after].present?
    scope = scope.where('created_at <= ?', parse_date(params[:created_before])) if params[:created_before].present?
    scope
  end

  def parse_date(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def serialize_log(log)
    {
      id: log.id,
      action: log.action,
      result: log.result,
      user_id: log.user_id,
      user_name: user_name_for(log.user_id),
      auditable_type: log.auditable_type,
      auditable_id: log.auditable_id,
      metadata: log.metadata,
      ip_address: log.ip_address,
      created_at: log.created_at
    }
  end

  def user_name_for(user_id)
    return nil if user_id.blank?

    @user_names ||= {}
    @user_names[user_id] ||= Current.account.users.find_by(id: user_id)&.name
  end
end
