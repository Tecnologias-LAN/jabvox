class Api::V1::Accounts::Jabvox::Analytics::RolesController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :ensure_admin
  before_action :set_role, only: %i[show update destroy]

  def index
    render json: scoped.order(:name_jabvox).map { |r| serialize(r) }
  end

  def show
    render json: serialize(@role)
  end

  def create
    role = scoped.new(role_params)
    role.account = Current.account
    role.is_system_jabvox = false
    role.slug_jabvox = role_params[:name_jabvox].to_s.parameterize.presence || "custom-#{SecureRandom.hex(3)}"
    if role.save
      seed_permissions(role)
      audit!(action: 'role.create', auditable: role, metadata: { name: role.name_jabvox })
      render json: serialize(role), status: :created
    else
      render json: { errors: role.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    return render json: { error: 'No se pueden editar roles del sistema' }, status: :forbidden if @role.is_system_jabvox

    if @role.update(role_params)
      audit!(action: 'role.update', auditable: @role)
      render json: serialize(@role)
    else
      render json: { errors: @role.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    return render json: { error: 'No se pueden eliminar roles del sistema' }, status: :forbidden if @role.is_system_jabvox

    @role.destroy!
    audit!(action: 'role.delete', auditable: @role)
    head :no_content
  end

  private

  def scoped
    Current.account.jabvox_analytics_roles
  end

  def set_role
    @role = scoped.find(params[:id])
  end

  def seed_permissions(role)
    JabvoxAnalyticsPermission::KEYS.each do |key|
      role.permissions.create!(account: Current.account, permission_key_jabvox: key, granted_jabvox: false)
    end
  end

  def role_params
    params.require(:role).permit(:name_jabvox, :description_jabvox)
  end

  def serialize(role)
    {
      id: role.id,
      name_jabvox: role.name_jabvox,
      slug_jabvox: role.slug_jabvox,
      is_system_jabvox: role.is_system_jabvox,
      description_jabvox: role.description_jabvox,
      grants: role.grants
    }
  end
end
