class Api::V1::Accounts::Jabvox::Tasks::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_tasks')

    render json: { error: 'El módulo de Tareas no está habilitado para esta cuenta' }, status: :forbidden
  end

  # Enforce a custom-role permission ONLY for users who actually have a custom role, so
  # standard agents keep their historical flow and admins always pass.
  def jabvox_gate!(key)
    return if Current.account_user&.custom_role.nil?

    jabvox_authorize!(key)
  end

  # Sections previously reserved to admins now also accept the jabvox_tasks_manage grant.
  # Admins keep passing; anyone else needs the custom-role permission.
  def ensure_admin
    return if Current.account_user&.administrator?
    return if Current.account_user&.custom_role&.grants?('jabvox_tasks_manage')

    render json: { error: 'Solo los administradores pueden gestionar esta sección' }, status: :forbidden
  end
end
