# CRUD de infaltables de QA, agrupados por tipificación. Lectura para quien tiene
# acceso al módulo; crear/editar/borrar requiere la capacidad de gestión.
class Api::V1::Accounts::Jabvox::AudioAnalysis::InfaltablesController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_access
  before_action :ensure_can_manage, only: [:create, :update, :destroy, :bulk_replace]
  before_action :set_infaltable, only: [:update, :destroy]

  # Una tipificación no necesita cientos de infaltables; esta cota evita abusos.
  MAX_INFALTABLES = 100

  # GET /infaltables?typification_id=... — lista los de una tipificación (o todos).
  def index
    scope = Current.account.jabvox_audio_infaltables.ordered
    scope = scope.where(typification_id: params[:typification_id]) if params[:typification_id].present?
    render json: { infaltables: scope.map { |i| serialize(i) } }
  end

  def create
    typification = Current.account.jabvox_typifications.find(infaltable_params[:typification_id])
    infaltable = typification.audio_infaltables.create!(
      infaltable_params.merge(account: Current.account, created_by: current_user)
    )
    render json: serialize(infaltable), status: :created
  end

  def update
    @infaltable.update!(infaltable_params.except(:typification_id))
    render json: serialize(@infaltable)
  end

  def destroy
    @infaltable.destroy!
    head :no_content
  end

  # PUT /infaltables/bulk_replace — reemplaza en bloque la lista de una
  # tipificación (útil para importar/pegar varios de una vez). Transaccional.
  # rubocop:disable Metrics/AbcSize
  def bulk_replace
    typification = Current.account.jabvox_typifications.find(params[:typification_id])
    items = Array(params[:items]).first(MAX_INFALTABLES)
    ActiveRecord::Base.transaction do
      typification.audio_infaltables.delete_all
      items.each_with_index do |item, i|
        next if item[:text].to_s.strip.blank?

        typification.audio_infaltables.create!(
          account: Current.account, created_by: current_user,
          text: item[:text].to_s.strip, position: i,
          optional: ActiveModel::Type::Boolean.new.cast(item[:optional]) || false
        )
      end
    end
    render json: { infaltables: typification.audio_infaltables.ordered.map { |i| serialize(i) } }
  end
  # rubocop:enable Metrics/AbcSize

  private

  def set_infaltable
    @infaltable = Current.account.jabvox_audio_infaltables.find(params[:id])
  end

  def infaltable_params
    params.require(:infaltable).permit(:typification_id, :text, :position, :optional, :active)
  end

  def serialize(inf)
    {
      id: inf.id, typification_id: inf.typification_id, text: inf.text,
      position: inf.position, optional: inf.optional, active: inf.active
    }
  end
end
