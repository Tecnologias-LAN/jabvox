# frozen_string_literal: true

# Sedes del calendario. Solo el administrador las gestiona: una sede define la zona horaria
# y el horario comercial que ve todo el equipo, así que no se delega en un rol.
#
# Leer sí está abierto a cualquier miembro: el calendario necesita saber qué sedes hay para
# filtrar y para sombrear el horario.
class Api::V1::Accounts::Jabvox::BranchesController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_calendar'

  before_action :set_branch, only: %i[show update destroy]
  before_action :ensure_admin!, only: %i[create update destroy]

  def index
    render json: scoped.ordered.includes(:hours, :manager_users).map { |b| serialize(b) }
  end

  def show
    render json: serialize(@branch)
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def create
    branch = scoped.new(branch_params)
    branch.created_by = current_user
    if branch.save
      sync_hours(branch)
      sync_managers(branch)
      render json: serialize(branch.reload), status: :created
    else
      render json: { errors: branch.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @branch.update(branch_params)
      sync_hours(@branch) if params.key?(:hours)
      sync_managers(@branch) if params.key?(:manager_ids)
      render json: serialize(@branch.reload)
    else
      render json: { errors: @branch.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @branch.destroy!
    head :no_content
  end

  private

  def scoped
    Current.account.jabvox_branches
  end

  def set_branch
    @branch = scoped.find(params[:id])
  end

  def ensure_admin!
    return if Current.account_user&.administrator?

    render json: { error: 'No tienes permiso para esta acción' }, status: :forbidden
  end

  def branch_params
    params.require(:branch).permit(:name_jabvox, :timezone_jabvox, :color_jabvox,
                                   :address_jabvox, :active_jabvox, :position_jabvox)
  end

  # El horario llega entero y reemplaza al anterior: es un calendario semanal, se edita
  # como un todo y no tiene sentido parchear franja a franja.
  #
  # En transacción y con `create!`: antes se borraba el horario anterior y las franjas
  # inválidas se descartaban en silencio devolviendo 200, así que el admin perdía lo que
  # tenía y creía haber guardado. Ahora o entra todo o no se toca nada.
  def sync_hours(branch)
    branch.transaction do
      branch.hours.destroy_all
      Array(params[:hours]).each do |row|
        branch.hours.create!(row.permit(:day_of_week, :open_minute, :close_minute).to_h)
      end
    end
  end

  # Solo usuarios de la cuenta: el modelo lo valida, aquí se filtra para no fallar por uno
  # que ya no exista (un responsable borrado no debe impedir guardar la sede).
  def sync_managers(branch)
    ids = Array(params[:manager_ids]).map(&:to_i) & Current.account.users.pluck(:id)
    branch.transaction do
      branch.managers.destroy_all
      ids.each { |user_id| branch.managers.create!(user_id: user_id) }
    end
  end

  def serialize(branch)
    {
      id: branch.id,
      name_jabvox: branch.name_jabvox,
      timezone_jabvox: branch.timezone_jabvox,
      color_jabvox: branch.color_jabvox,
      address_jabvox: branch.address_jabvox,
      active_jabvox: branch.active_jabvox,
      position_jabvox: branch.position_jabvox,
      manager_ids: branch.manager_users.map(&:id),
      manager_names: branch.manager_users.map(&:name),
      hours: branch.hours.order(:day_of_week, :open_minute).map do |h|
        { day_of_week: h.day_of_week, open_minute: h.open_minute, close_minute: h.close_minute }
      end
    }
  end
end
