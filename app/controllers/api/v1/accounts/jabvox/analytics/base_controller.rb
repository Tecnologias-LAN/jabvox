class Api::V1::Accounts::Jabvox::Analytics::BaseController < Api::V1::Accounts::BaseController
  include Jabvox::Analytics::Auditable

  before_action :check_feature_enabled
  before_action :ensure_roles_seeded
  before_action :ensure_can_access

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_analytics')

    render json: { error: 'El módulo Analytics no está habilitado para esta cuenta' }, status: :forbidden
  end

  # Lazily seed the 4 system roles + grants on first use within an account.
  def ensure_roles_seeded
    return if JabvoxAnalyticsRole.exists?(account_id: Current.account.id, is_system_jabvox: true)

    Jabvox::Analytics::RoleSeeder.new(Current.account).call
  end

  def permission_resolver
    @permission_resolver ||= Jabvox::Analytics::PermissionResolver.new(current_user, Current.account)
  end

  def ensure_can_access
    return if permission_resolver.can_access?

    render json: { error: 'No tienes acceso al módulo Analytics' }, status: :forbidden
  end

  # Guard a controller action behind a capability key.
  def authorize!(key)
    return if permission_resolver.can?(key)

    render json: { error: "No tienes permiso para esta acción (#{key})" }, status: :forbidden
  end

  # Admin-only sections (roles, permissions, audit logs).
  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Solo los administradores pueden gestionar esta sección' }, status: :forbidden
  end
end
