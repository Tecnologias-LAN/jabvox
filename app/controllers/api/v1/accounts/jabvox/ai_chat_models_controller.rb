class Api::V1::Accounts::Jabvox::AiChatModelsController < Api::V1::Accounts::BaseController
  before_action :fetch_model, only: [:update, :destroy, :set_default, :test_connection]
  before_action :authorize_model

  def index
    @models = Current.account.jabvox_ai_chat_models.ordered
    render json: @models.map { |m| model_json(m) }
  end

  def create
    @model = Current.account.jabvox_ai_chat_models.new(model_params)
    @model.save!
    render json: model_json(@model), status: :created
  end

  def update
    @model.update!(model_params)
    if model_params[:is_default_jabvox] == true || model_params[:is_default_jabvox] == 'true'
      Current.account.jabvox_ai_chat_models.where.not(id: @model.id).update_all(is_default_jabvox: false)
    end
    render json: model_json(@model)
  end

  def destroy
    @model.destroy!
    head :ok
  end

  def set_default
    Current.account.jabvox_ai_chat_models.update_all(is_default_jabvox: false)
    @model.update!(is_default_jabvox: true)
    render json: model_json(@model)
  end

  def test_connection
    if @model.api_key_jabvox.blank?
      render json: { success: false, error: 'API key is required to test connection' }, status: :unprocessable_entity
      return
    end

    client = build_test_client(@model)
    start = Time.now.to_f
    client.chat(parameters: { model: @model.model_jabvox, messages: [{ role: 'user', content: 'Hola' }], max_tokens: 5 })
    latency_ms = ((Time.now.to_f - start) * 1000).round
    render json: { success: true, latency_ms: latency_ms }
  rescue StandardError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_model
    @model = Current.account.jabvox_ai_chat_models.find(params[:id])
  end

  def authorize_model
    authorize @model || JabvoxAiChatModel
  end

  def model_params
    params.require(:jabvox_ai_chat_model).permit(:name_jabvox, :provider_jabvox, :model_jabvox, :api_key_jabvox, :base_url_jabvox, :is_default_jabvox)
  end

  def model_json(m)
    {
      id: m.id,
      name_jabvox: m.name_jabvox,
      provider_jabvox: m.provider_jabvox,
      model_jabvox: m.model_jabvox,
      api_key_masked: m.api_key_jabvox.present? ? "***#{m.api_key_jabvox.last(4)}" : nil,
      base_url_jabvox: m.base_url_jabvox,
      is_default_jabvox: m.is_default_jabvox,
      created_at: m.created_at
    }
  end

  def build_test_client(model)
    require 'openai'
    opts = { access_token: model.api_key_jabvox.to_s }
    opts[:uri_base] = model.base_url_jabvox if model.base_url_jabvox.present?
    OpenAI::Client.new(**opts)
  end
end
