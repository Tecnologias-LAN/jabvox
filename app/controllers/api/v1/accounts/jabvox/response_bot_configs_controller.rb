class Api::V1::Accounts::Jabvox::ResponseBotConfigsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :set_config, only: [:update, :destroy]

  def index
    @configs = Current.account.jabvox_response_bot_configs.includes(:inbox)
    authorize JabvoxResponseBotConfig
    render json: @configs.map { |c| config_json(c) }
  end

  def create
    @config = Current.account.jabvox_response_bot_configs.build(config_params)
    authorize @config
    @config.save!
    render json: config_json(@config), status: :created
  end

  def update
    authorize @config
    @config.update!(config_params)
    render json: config_json(@config)
  end

  def destroy
    authorize @config
    @config.destroy!
    head :no_content
  end

  def setup_labels
    authorize JabvoxResponseBotConfig
    active_labels = JabvoxResponseBotConfig::LABEL_CATEGORIES
    created = []
    active_labels.each do |title|
      next if Current.account.labels.exists?(title: title)

      Current.account.labels.create!(title: title, color: default_label_color(title), show_on_sidebar: true)
      created << title
    end
    render json: { created: created }
  end

  private

  def set_config
    @config = Current.account.jabvox_response_bot_configs.find(params[:id])
  end

  def config_params
    params.require(:config).permit(
      :inbox_id, :jabvox_response_bot_seat_id, :enabled_jabvox,
      :jabvox_ai_chat_model_id, :jabvox_audio_model_id,
      active_labels_jabvox: []
    )
  end

  def config_json(config)
    {
      id: config.id,
      inbox_id: config.inbox_id,
      jabvox_response_bot_seat_id: config.jabvox_response_bot_seat_id,
      enabled_jabvox: config.enabled_jabvox,
      active_labels_jabvox: config.active_labels_jabvox || JabvoxResponseBotConfig::LABEL_CATEGORIES,
      jabvox_ai_chat_model_id: config.jabvox_ai_chat_model_id,
      jabvox_audio_model_id: config.jabvox_audio_model_id
    }
  end

  def default_label_color(title)
    {
      'proceso_venta' => '#10b981',
      'proceso_pago' => '#3b82f6',
      'quejas_y_reclamos' => '#ef4444',
      'soporte' => '#f59e0b'
    }[title] || '#6b7280'
  end
end
