class Api::V1::Accounts::Jabvox::ResponseBotConfigsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  before_action :ensure_module_permission
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

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    return if Current.account_user&.custom_role.nil?

    jabvox_authorize!('jabvox_response_bot_manage')
  end

  def set_config
    @config = Current.account.jabvox_response_bot_configs.find(params[:id])
  end

  def config_params
    params.require(:config).permit(
      :inbox_id, :jabvox_response_bot_seat_id, :jabvox_response_bot_role_id,
      :enabled_jabvox, :jabvox_ai_chat_model_id, :jabvox_audio_model_id, :jabvox_image_model_id,
      :name_jabvox, :description_jabvox,
      :google_maps_api_key_jabvox, :company_address_jabvox, :price_per_km_jabvox,
      active_labels_jabvox: []
    )
  end

  def config_json(config)
    {
      id: config.id,
      inbox_id: config.inbox_id,
      name_jabvox: config.name_jabvox,
      description_jabvox: config.description_jabvox,
      jabvox_response_bot_seat_id: config.jabvox_response_bot_seat_id,
      jabvox_response_bot_role_id: config.jabvox_response_bot_role_id,
      enabled_jabvox: config.enabled_jabvox,
      active_labels_jabvox: config.active_labels_jabvox || JabvoxResponseBotConfig::LABEL_CATEGORIES,
      jabvox_ai_chat_model_id: config.jabvox_ai_chat_model_id,
      jabvox_audio_model_id: config.jabvox_audio_model_id,
      jabvox_image_model_id: config.jabvox_image_model_id,
      google_maps_api_key_jabvox: config.google_maps_api_key_jabvox,
      company_address_jabvox: config.company_address_jabvox,
      price_per_km_jabvox: config.price_per_km_jabvox
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
