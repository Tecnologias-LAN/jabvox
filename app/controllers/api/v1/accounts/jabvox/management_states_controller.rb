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

  # Portable JSON of every management state + its questions (no DB ids), the
  # same shape `import` accepts — export from one account, import in another.
  def export
    states = Current.account.jabvox_management_states.ordered.includes(:questions)
    render json: {
      version: 1,
      exported_at: Time.current.iso8601,
      states: states.map { |state| export_state(state) }
    }
  end

  def import
    result = Jabvox::ManagementStatesImportService.new(Current.account, import_payload).call
    if result.valid?
      render json: { created: result.created, updated: result.updated }
    else
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
  end

  private

  def import_payload
    raw = params[:data]
    raw = raw.permit!.to_h if raw.respond_to?(:permit!)
    raw.is_a?(Hash) ? raw : {}
  end

  def export_state(state)
    {
      name_jabvox: state.name_jabvox,
      state_group_jabvox: state.state_group_jabvox,
      usage_info_jabvox: state.usage_info_jabvox,
      managed_jabvox: state.managed_jabvox,
      contact_jabvox: state.contact_jabvox,
      effective_contact_jabvox: state.effective_contact_jabvox,
      advisory_jabvox: state.advisory_jabvox,
      service_type_jabvox: state.service_type_jabvox,
      positivity_level_jabvox: state.positivity_level_jabvox,
      color_jabvox: state.color_jabvox,
      is_active_jabvox: state.is_active_jabvox,
      note_mode: state.note_mode,
      position_jabvox: state.position_jabvox,
      questions: state.questions.ordered.map do |q|
        { label: q.label, question_type: q.question_type, required: q.required,
          options: q.options, position: q.position }
      end
    }
  end

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_management_states_manage')
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
      :state_group_jabvox, :usage_info_jabvox, :managed_jabvox, :contact_jabvox,
      :effective_contact_jabvox, :advisory_jabvox, :service_type_jabvox, :positivity_level_jabvox,
      questions_attributes: [:id, :label, :question_type, :required, :position, :_destroy, { options: [] }]
    )
  end
end
