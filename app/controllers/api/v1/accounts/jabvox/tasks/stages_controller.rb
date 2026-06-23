class Api::V1::Accounts::Jabvox::Tasks::StagesController < Api::V1::Accounts::Jabvox::Tasks::BaseController
  before_action :set_board
  before_action :set_stage, only: %i[update destroy]

  def index
    render json: @board.stages.ordered.map { |s| serialize(s) }
  end

  def create
    stage = @board.stages.new(stage_params)
    stage.account = Current.account
    if stage.save
      render json: serialize(stage), status: :created
    else
      render json: { errors: stage.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @stage.update(stage_params)
      render json: serialize(@stage)
    else
      render json: { errors: @stage.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @stage.destroy!
    head :no_content
  end

  private

  def set_board
    @board = Current.account.jabvox_task_boards.find(params[:board_id])
  end

  def set_stage
    @stage = @board.stages.find(params[:id])
  end

  def stage_params
    params.require(:stage).permit(:name_jabvox, :color_jabvox, :position_jabvox)
  end

  def serialize(stage)
    {
      id: stage.id, name_jabvox: stage.name_jabvox, color_jabvox: stage.color_jabvox,
      position_jabvox: stage.position_jabvox
    }
  end
end
