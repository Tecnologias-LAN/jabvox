# CRUD de los mapeos código→tipificación y código→asesor que se configuran desde
# la visual. El parser de nombre de archivo los usa para resolver la llamada sin
# asumir nada por código.
class Api::V1::Accounts::Jabvox::AudioAnalysis::CodeMappingsController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_access
  before_action :ensure_can_manage, only: [:create, :update, :destroy]
  before_action :set_mapping, only: [:update, :destroy]

  # GET /code_mappings?kind=typification|advisor
  def index
    scope = Current.account.jabvox_audio_code_mappings.order(:code)
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    render json: { mappings: scope.map { |m| serialize(m) } }
  end

  def create
    mapping = Current.account.jabvox_audio_code_mappings.new(mapping_params)
    mapping.created_by = current_user
    assign_target(mapping)
    mapping.save!
    render json: serialize(mapping), status: :created
  end

  def update
    @mapping.assign_attributes(mapping_params)
    assign_target(@mapping)
    @mapping.save!
    render json: serialize(@mapping)
  end

  def destroy
    @mapping.destroy!
    head :no_content
  end

  private

  def set_mapping
    @mapping = Current.account.jabvox_audio_code_mappings.find(params[:id])
  end

  def mapping_params
    params.require(:code_mapping).permit(:kind, :code)
  end

  # El target (tipificación o asesor) se valida contra la cuenta, nunca se confía
  # un id ajeno del cliente.
  def assign_target(mapping)
    if mapping.kind == 'typification'
      tid = params.dig(:code_mapping, :typification_id)
      mapping.typification = Current.account.jabvox_typifications.find_by(id: tid)
      mapping.advisor = nil
    elsif mapping.kind == 'advisor'
      aid = params.dig(:code_mapping, :advisor_id)
      mapping.advisor = Current.account.jabvox_audio_advisors.find_by(id: aid)
      mapping.typification = nil
    end
  end

  def serialize(mapping)
    {
      id: mapping.id, kind: mapping.kind, code: mapping.code,
      typification_id: mapping.typification_id, typification_name: mapping.typification&.name,
      advisor_id: mapping.advisor_id, advisor_name: mapping.advisor&.name
    }
  end
end
