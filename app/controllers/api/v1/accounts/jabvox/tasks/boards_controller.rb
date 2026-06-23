class Api::V1::Accounts::Jabvox::Tasks::BoardsController < Api::V1::Accounts::Jabvox::Tasks::BaseController
  before_action :set_board, only: %i[show update destroy]

  def index
    render json: scoped.ordered.map { |b| serialize(b) }
  end

  def show
    render json: serialize(@board, detailed: true)
  end

  def create
    board = scoped.new(board_params)
    board.account = Current.account
    board.created_by = current_user
    if board.save
      render json: serialize(board, detailed: true), status: :created
    else
      render json: { errors: board.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @board.update(board_params)
      render json: serialize(@board, detailed: true)
    else
      render json: { errors: @board.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @board.destroy!
    head :no_content
  end

  private

  def scoped
    Current.account.jabvox_task_boards
  end

  def set_board
    @board = scoped.find(params[:id])
  end

  def board_params
    params.require(:board).permit(:name_jabvox, :description_jabvox, :position_jabvox, :is_active_jabvox)
  end

  def serialize(board, detailed: false)
    base = {
      id: board.id, name_jabvox: board.name_jabvox, description_jabvox: board.description_jabvox,
      position_jabvox: board.position_jabvox, is_active_jabvox: board.is_active_jabvox
    }
    return base unless detailed

    base.merge(stages: board.stages.ordered.map { |s| stage_json(s) })
  end

  def stage_json(stage)
    {
      id: stage.id, name_jabvox: stage.name_jabvox, color_jabvox: stage.color_jabvox,
      position_jabvox: stage.position_jabvox
    }
  end
end
