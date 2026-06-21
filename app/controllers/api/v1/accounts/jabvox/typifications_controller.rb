class Api::V1::Accounts::Jabvox::TypificationsController < Api::V1::Accounts::BaseController
  before_action :set_typification, only: [:update, :destroy]

  # Shared across click-to-call, CDR and Audio Analysis pipelines.
  def index
    scope = Current.account.jabvox_typifications.ordered
    scope = scope.active if ActiveModel::Type::Boolean.new.cast(params[:active_only])
    render json: { typifications: scope.map { |tp| serialize(tp) } }
  end

  def create
    typification = Current.account.jabvox_typifications.create!(typification_params)
    render json: serialize(typification), status: :created
  end

  def update
    @typification.update!(typification_params)
    render json: serialize(@typification)
  end

  def destroy
    @typification.destroy!
    head :no_content
  end

  private

  def set_typification
    @typification = Current.account.jabvox_typifications.find(params[:id])
  end

  def typification_params
    params.require(:typification).permit(:name, :description, :is_active)
  end

  def serialize(typification)
    {
      id: typification.id,
      name: typification.name,
      description: typification.description,
      is_active: typification.is_active
    }
  end
end
