class Api::V1::Accounts::Jabvox::ManagementStatesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_state, only: [:show, :update, :destroy]
  before_action :check_authorization

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

  def fetch_state
    @state = Current.account.jabvox_management_states.find(params[:id])
  end

  def check_authorization
    authorize @state || JabvoxManagementState
  end

  def state_params
    params.require(:state).permit(:name_jabvox, :color_jabvox, :is_active_jabvox, :position_jabvox)
  end
end
