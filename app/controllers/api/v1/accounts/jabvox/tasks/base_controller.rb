class Api::V1::Accounts::Jabvox::Tasks::BaseController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_tasks')

    render json: { error: 'El módulo de Tareas no está habilitado para esta cuenta' }, status: :forbidden
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Solo los administradores pueden gestionar esta sección' }, status: :forbidden
  end
end
