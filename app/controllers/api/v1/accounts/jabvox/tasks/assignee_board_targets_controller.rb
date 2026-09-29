# Destinos de la copia por responsable de un tablero: para cada dueño, a cuál de SUS
# tableros se copia la tarea. Solo admin o rol con jabvox_tasks_manage, como el resto de
# la configuración del tablero.
class Api::V1::Accounts::Jabvox::Tasks::AssigneeBoardTargetsController < Api::V1::Accounts::Jabvox::Tasks::BaseController
  before_action :ensure_admin
  before_action :set_board
  before_action :set_target, only: %i[update destroy]

  def index
    render json: @board.assignee_board_targets.map { |t| serialize(t) }
  end

  # Tableros que pueden ser destino: los que tienen dueño, agrupados por dueño, para que
  # el frontend pueda ofrecer "a cuál de los tableros de este usuario".
  def available_boards
    boards = Current.account.jabvox_task_boards.where.not(owner_id: nil).ordered
    render json: boards.map { |b| { id: b.id, name_jabvox: b.name_jabvox, owner_id: b.owner_id } }
  end

  def create
    target = @board.assignee_board_targets.new(target_params)
    target.account = Current.account
    if target.save
      render json: serialize(target), status: :created
    else
      render json: { errors: target.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @target.update(target_params)
      render json: serialize(@target)
    else
      render json: { errors: @target.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @target.destroy!
    head :no_content
  end

  private

  def set_board
    @board = Current.account.jabvox_task_boards.find(params[:board_id])
  end

  def set_target
    @target = @board.assignee_board_targets.find(params[:id])
  end

  def target_params
    params.require(:target).permit(:owner_id, :target_board_id)
  end

  def serialize(target)
    {
      id: target.id, owner_id: target.owner_id, target_board_id: target.target_board_id,
      source_board_id: target.source_board_id
    }
  end
end
