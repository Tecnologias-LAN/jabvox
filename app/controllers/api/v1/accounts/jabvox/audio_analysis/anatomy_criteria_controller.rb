# CRUD de criterios de Anatomía / Cercanía. Si la cuenta aún no tiene ninguno,
# el index siembra los 12 por defecto para que haya un punto de partida editable.
class Api::V1::Accounts::Jabvox::AudioAnalysis::AnatomyCriteriaController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_access
  before_action :ensure_can_manage, only: [:create, :update, :destroy, :seed_defaults]
  before_action :set_criterion, only: [:update, :destroy]

  def index
    JabvoxAudioAnatomyCriterion.seed_defaults!(Current.account, created_by: current_user) if seed_allowed?
    render json: { criteria: Current.account.jabvox_audio_anatomy_criteria.ordered.map { |c| serialize(c) } }
  end

  def create
    criterion = Current.account.jabvox_audio_anatomy_criteria.create!(
      criterion_params.merge(created_by: current_user)
    )
    render json: serialize(criterion), status: :created
  end

  def update
    @criterion.update!(criterion_params)
    render json: serialize(@criterion)
  end

  def destroy
    @criterion.destroy!
    head :no_content
  end

  # POST /anatomy_criteria/seed_defaults — restaura los 12 por defecto cuando la
  # cuenta no tiene ninguno (no duplica si ya existen).
  def seed_defaults
    JabvoxAudioAnatomyCriterion.seed_defaults!(Current.account, created_by: current_user)
    render json: { criteria: Current.account.jabvox_audio_anatomy_criteria.ordered.map { |c| serialize(c) } }
  end

  private

  # Siembra en el primer index solo si quien mira puede gestionar (para no crear
  # datos por una simple lectura de un agente sin permisos de gestión).
  def seed_allowed?
    jabvox_can?('jabvox_audio_manage') && !Current.account.jabvox_audio_anatomy_criteria.exists?
  end

  def set_criterion
    @criterion = Current.account.jabvox_audio_anatomy_criteria.find(params[:id])
  end

  def criterion_params
    params.require(:criterion).permit(:name, :description, :positive_signal, :opportunity_signal, :position, :active)
  end

  def serialize(crit)
    {
      id: crit.id, name: crit.name, description: crit.description,
      positive_signal: crit.positive_signal, opportunity_signal: crit.opportunity_signal,
      position: crit.position, active: crit.active
    }
  end
end
