class Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_audio_analysis')

    render json: { error: 'Jabvox Audio Analysis feature is not enabled for this account' }, status: :forbidden
  end

  def permission
    @permission ||= JabvoxAudioPermission.find_by(account_id: Current.account.id, user_id: current_user.id)
  end

  def admin?
    Current.account_user&.administrator? || false
  end

  def can_access?
    admin? || permission&.can_access
  end

  def can_view_reports?
    admin? || permission&.can_view_reports
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

  def ensure_admin
    return if admin?

    render json: { error: 'Solo los administradores pueden gestionar esta configuración' }, status: :forbidden
  end
end
