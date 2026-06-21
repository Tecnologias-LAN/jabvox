class Api::V1::Accounts::Jabvox::Cdr::BaseController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_cdr')

    render json: { error: 'Jabvox CDR feature is not enabled for this account' }, status: :forbidden
  end

  # Admins always have access; agents need an explicit can_view permission.
  def can_view_reports?
    return true if Current.account_user&.administrator?

    JabvoxCdrReportPermission.exists?(account_id: Current.account.id, user_id: current_user.id, can_view: true)
  end

  def ensure_can_view_reports
    return if can_view_reports?

    render json: { error: 'No tienes permiso para ver los reportes CDR' }, status: :forbidden
  end

  # Configuration / pipelines / permissions are admin-only.
  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Solo los administradores pueden gestionar la configuración CDR' }, status: :forbidden
  end
end
