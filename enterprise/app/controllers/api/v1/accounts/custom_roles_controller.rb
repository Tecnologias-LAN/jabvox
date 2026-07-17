class Api::V1::Accounts::CustomRolesController < Api::V1::Accounts::EnterpriseAccountsController
  # The whole module is gated by the account's custom_roles feature: with the
  # module off, the API is closed too (the frontend route guard already blocks
  # the tab, this covers direct API access).
  before_action :check_custom_roles_feature
  before_action :fetch_custom_role, only: [:show, :update, :destroy]
  before_action :check_authorization
  # Permissions from disabled modules can't be granted (mirrors the form, which
  # only shows groups for enabled modules). Permissions the role already holds
  # are grandfathered so editing an old role never breaks.
  before_action :check_permissions_available, only: [:create, :update]

  def index
    @custom_roles = Current.account.custom_roles
  end

  def show; end

  def create
    @custom_role = Current.account.custom_roles.create!(permitted_params)
  end

  def update
    @custom_role.update!(permitted_params)
  end

  def destroy
    @custom_role.destroy!
    head :ok
  end

  def permitted_params
    params.require(:custom_role).permit(:name, :description, permissions: [])
  end

  def fetch_custom_role
    # find (not find_by) so an unknown/foreign id renders 404 instead of a nil
    # that would crash update!/destroy! with a 500.
    @custom_role = Current.account.custom_roles.find(params[:id])
  end

  def check_custom_roles_feature
    return if Current.account.feature_enabled?('custom_roles')

    render json: { error: 'Custom roles is not enabled for this account.' }, status: :forbidden
  end

  def check_permissions_available
    requested = Array(params.dig(:custom_role, :permissions)).map(&:to_s)
    grandfathered = @custom_role ? Array(@custom_role.permissions) : []
    blocked = (requested - grandfathered).reject { |p| CustomRole.permission_available?(Current.account, p) }
    return if blocked.empty?

    render json: { error: "Permissions belong to disabled modules: #{blocked.join(', ')}" },
           status: :unprocessable_entity
  end
end
