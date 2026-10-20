# CRUD de asesores del módulo de QA. Un asesor puede vincularse a un usuario del
# CRM (user_id) o existir solo en el módulo (nombre + external_id).
class Api::V1::Accounts::Jabvox::AudioAnalysis::AdvisorsController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_access
  before_action :ensure_can_manage, only: [:create, :update, :destroy, :import_users]
  before_action :set_advisor, only: [:update, :destroy]

  def index
    render json: { advisors: Current.account.jabvox_audio_advisors.ordered.map { |a| serialize(a) } }
  end

  def create
    advisor = Current.account.jabvox_audio_advisors.create!(
      advisor_params.merge(created_by: current_user, user_id: safe_user_id)
    )
    render json: serialize(advisor), status: :created
  end

  def update
    @advisor.update!(advisor_params.merge(user_id: safe_user_id))
    render json: serialize(@advisor)
  end

  def destroy
    @advisor.destroy!
    head :no_content
  end

  # POST /advisors/import_users — crea un asesor por cada usuario del CRM que aún
  # no esté vinculado, para arrancar rápido en cuentas que sí usan el CRM.
  def import_users
    created = 0
    Current.account.users.find_each do |user|
      next if Current.account.jabvox_audio_advisors.exists?(user_id: user.id)

      Current.account.jabvox_audio_advisors.create!(name: user.name, user_id: user.id, created_by: current_user)
      created += 1
    end
    render json: { created: created, advisors: Current.account.jabvox_audio_advisors.ordered.map { |a| serialize(a) } }
  end

  private

  def set_advisor
    @advisor = Current.account.jabvox_audio_advisors.find(params[:id])
  end

  def advisor_params
    params.require(:advisor).permit(:name, :external_id, :active)
  end

  # Nunca se confía un user_id del cliente: debe pertenecer a la cuenta.
  def safe_user_id
    uid = params.dig(:advisor, :user_id)
    return nil if uid.blank?

    Current.account.users.exists?(uid) ? uid.to_i : nil
  end

  def serialize(advisor)
    {
      id: advisor.id, name: advisor.name, external_id: advisor.external_id,
      user_id: advisor.user_id, user_name: advisor.user&.name, active: advisor.active
    }
  end
end
