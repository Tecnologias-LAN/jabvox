class Api::V1::Accounts::Jabvox::TypificationsController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :ensure_module_permission
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

  # Portable JSON of every typification (no DB ids), the same shape `import`
  # accepts — export from one account, import into another.
  def export
    typifications = Current.account.jabvox_typifications.ordered
    render json: {
      version: 1,
      exported_at: Time.current.iso8601,
      typifications: typifications.map do |tp|
        { name: tp.name, description: tp.description, is_active: tp.is_active }
      end
    }
  end

  # Imports typifications from an uploaded JSON. The service re-validates every
  # field against a strict whitelist; the file is data only (nothing executes).
  def import
    result = Jabvox::TypificationsImportService.new(Current.account, import_payload).call
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

  # Writes require the manage permission; export/import are management actions
  # too (they pull or replace the whole catalog), so they require it as well.
  # index stays open to any account member. Admins always pass.
  def ensure_module_permission
    if %w[export import].include?(action_name)
      jabvox_authorize!('jabvox_typifications_manage')
    else
      jabvox_authorize_write!('jabvox_typifications_manage')
    end
  end

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
