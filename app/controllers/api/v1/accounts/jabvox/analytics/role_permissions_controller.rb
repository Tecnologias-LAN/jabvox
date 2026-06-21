# Manages the per-role permission grant matrix (role x permission_key -> granted).
class Api::V1::Accounts::Jabvox::Analytics::RolePermissionsController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :ensure_admin

  def index
    roles = Current.account.jabvox_analytics_roles.order(:name_jabvox)
    render json: {
      keys: JabvoxAnalyticsPermission::KEYS,
      roles: roles.map do |r|
        { id: r.id, name_jabvox: r.name_jabvox, slug_jabvox: r.slug_jabvox, is_system_jabvox: r.is_system_jabvox, grants: r.grants }
      end
    }
  end

  # PATCH role_permissions/:id  { grants: { "create" => true, ... } }
  def update
    role = Current.account.jabvox_analytics_roles.find(params[:id])
    return render json: { error: 'No se pueden editar roles del sistema' }, status: :forbidden if role.is_system_jabvox

    grants = params.require(:grants).permit(*JabvoxAnalyticsPermission::KEYS).to_h
    apply_grants(role, grants)
    audit!(action: 'permission.change', auditable: role, metadata: { grants: grants })
    render json: { id: role.id, grants: role.reload.grants }
  end

  private

  def apply_grants(role, grants)
    grants.each do |key, value|
      perm = role.permissions.find_or_initialize_by(account_id: Current.account.id, permission_key_jabvox: key)
      perm.granted_jabvox = ActiveModel::Type::Boolean.new.cast(value)
      perm.save!
    end
  end
end
