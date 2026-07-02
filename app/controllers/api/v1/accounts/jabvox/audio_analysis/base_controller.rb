class Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_audio_analysis')

    render json: { error: 'Jabvox Audio Analysis feature is not enabled for this account' }, status: :forbidden
  end

  # All predicates below rely on the JabvoxPermissions concern, which grants
  # every capability to administrators and otherwise checks the account user's
  # custom role.
  def can_access?
    jabvox_can?('jabvox_audio_access')
  end

  def can_view_reports?
    jabvox_can?('jabvox_audio_view_reports')
  end

  # Storages / pipelines / jobs / access management require module access.
  def ensure_can_access
    return if can_access?

    render json: { error: 'No tienes acceso al módulo de análisis de audios' }, status: :forbidden
  end

  def ensure_can_view_reports
    return if can_view_reports?

    render json: { error: 'No tienes permiso para ver los reportes de audio' }, status: :forbidden
  end

  # Managing pipelines / storages / jobs / assignments requires the manage
  # capability (admins always pass via the concern). Read access alone is not
  # enough to create/update/destroy configuration.
  def ensure_can_manage
    return if jabvox_can?('jabvox_audio_manage')

    render json: { error: 'No tienes permiso para gestionar el análisis de audios' }, status: :forbidden
  end
  alias ensure_admin ensure_can_manage
end
