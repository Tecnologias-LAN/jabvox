class Api::V1::Accounts::Jabvox::KanbanStagesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_funnel
  before_action :fetch_stage, only: [:update, :destroy]
  before_action :check_authorization

  def index
    @stages = policy_scope(@funnel.jabvox_kanban_stages.ordered)
  end

  def create
    @stage = @funnel.jabvox_kanban_stages.new(stage_params.merge(account_id: Current.account.id))
    @stage.save!
  end

  def update
    @stage.update!(stage_params)
    reorder_stages if params[:position_jabvox].present?
  end

  def destroy
    raise StandardError, 'Cannot delete the only stage in a funnel' if @funnel.jabvox_kanban_stages.count <= 1

    reassign_conversations_to_first_stage
    @stage.destroy!
    head :ok
  end

  private

  def fetch_funnel
    funnel_id = params[:funnel_id] || params[:kanban_funnel_id]
    @funnel = Current.account.jabvox_kanban_funnels.find(funnel_id)
  end

  def fetch_stage
    @stage = @funnel.jabvox_kanban_stages.find(params[:id])
  end

  def check_authorization
    authorize @stage || JabvoxKanbanStage
  end

  def stage_params
    params.require(:stage).permit(:name_jabvox, :description_jabvox, :position_jabvox, :color_jabvox)
  end

  def reorder_stages
    stages = @funnel.jabvox_kanban_stages.ordered.reject { |s| s.id == @stage.id }
    return if stages.empty?

    sql_case = stages.each_with_index.map { |s, i| "WHEN #{s.id} THEN #{i}" }.join(' ')
    # rubocop:disable Rails/SkipsModelValidations
    JabvoxKanbanStage.where(id: stages.map(&:id)).update_all("position_jabvox = CASE id #{sql_case} END")
    # rubocop:enable Rails/SkipsModelValidations
  end

  def reassign_conversations_to_first_stage
    first_stage = @funnel.jabvox_kanban_stages.where.not(id: @stage.id).order(:position_jabvox).first
    return unless first_stage

    # rubocop:disable Rails/SkipsModelValidations
    @stage.jabvox_kanban_conversation_stages.update_all(jabvox_kanban_stage_id: first_stage.id)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
