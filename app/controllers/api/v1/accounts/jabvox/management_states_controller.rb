class Api::V1::Accounts::Jabvox::ManagementStatesController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  skip_before_action :check_feature_enabled
  before_action :fetch_state, only: [:show, :update, :destroy]
  before_action :check_authorization
  before_action :ensure_module_permission

  def index
    @states = policy_scope(Current.account.jabvox_management_states.ordered)
  end

  def show; end

  def create
    @state = Current.account.jabvox_management_states.new(state_params)
    @state.save!
    render :show
  end

  def update
    @state.update!(state_params)
    render :show
  end

  def destroy
    @state.destroy!
    head :ok
  end

  private

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    return if Current.account_user&.custom_role.nil?

    jabvox_authorize!('jabvox_management_states_manage')
  end

  def fetch_state
    @state = Current.account.jabvox_management_states.find(params[:id])
  end

  def check_authorization
    authorize @state || JabvoxManagementState
  end

  def state_params
    params.require(:state).permit(
      :name_jabvox, :color_jabvox, :is_active_jabvox, :position_jabvox, :note_mode,
      questions_attributes: [:id, :label, :question_type, :required, :position, :_destroy, { options: [] }]
    )
  end
end
