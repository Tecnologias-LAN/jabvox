class Api::V1::Accounts::Jabvox::Cdr::PipelinesController < Api::V1::Accounts::Jabvox::Cdr::BaseController
  before_action :ensure_admin
  before_action :set_pipeline, only: [:show, :update, :destroy]

  def index
    render json: { pipelines: Current.account.jabvox_cdr_pipelines.ordered.map { |p| serialize(p) } }
  end

  def show
    render json: serialize(@pipeline)
  end

  def create
    pipeline = Current.account.jabvox_cdr_pipelines.create!(pipeline_params)
    render json: serialize(pipeline), status: :created
  end

  def update
    @pipeline.update!(pipeline_params)
    render json: serialize(@pipeline)
  end

  def destroy
    @pipeline.destroy!
    head :no_content
  end

  private

  def set_pipeline
    @pipeline = Current.account.jabvox_cdr_pipelines.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(
      :name, :transcription_model_id, :typification_id, :is_default,
      :timestamp_mode_jabvox, :segment_seconds_jabvox,
      stages_attributes: [:id, :name, :prompt, :llm_model_id, :position, :min_score, :_destroy]
    )
  end

  def serialize(pipeline)
    {
      id: pipeline.id,
      name: pipeline.name,
      transcription_model_id: pipeline.transcription_model_id,
      typification_id: pipeline.typification_id,
      is_default: pipeline.is_default,
      timestamp_mode_jabvox: pipeline.timestamp_mode_jabvox,
      segment_seconds_jabvox: pipeline.segment_seconds_jabvox,
      stages: pipeline.stages.map do |stage|
        {
          id: stage.id,
          name: stage.name,
          prompt: stage.prompt,
          llm_model_id: stage.llm_model_id,
          position: stage.position,
          min_score: stage.min_score
        }
      end
    }
  end
end
