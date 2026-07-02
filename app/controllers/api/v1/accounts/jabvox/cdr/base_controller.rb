class Api::V1::Accounts::Jabvox::Cdr::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_cdr')

    render json: { error: 'Jabvox CDR feature is not enabled for this account' }, status: :forbidden
  end

  # Admins always have access (handled by the concern); agents need the
  # 'jabvox_cdr_view_reports' capability granted through their custom role.
  def can_view_reports?
    jabvox_can?('jabvox_cdr_view_reports')
  end

  def ensure_can_view_reports
    return if can_view_reports?

    render json: { error: 'No tienes permiso para ver los reportes CDR' }, status: :forbidden
  end

  # Configuration / pipelines are gated by the 'jabvox_cdr_manage' capability
  # (admins always pass through the concern).
  def ensure_admin
    return if jabvox_can?('jabvox_cdr_manage')

    render json: { error: 'Solo los administradores pueden gestionar la configuración CDR' }, status: :forbidden
  end
end
