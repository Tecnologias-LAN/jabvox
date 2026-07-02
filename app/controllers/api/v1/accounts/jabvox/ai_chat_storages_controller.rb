# Manages the shared storage buckets (JabvoxAudioStorage) from AI Chat, so an
# account can configure buckets here without needing the Audio Analysis module
# enabled. It operates on the SAME model as Audio Analysis storages — the two
# modules share one set of buckets — but is gated by AI Chat's own permission
# (jabvox_ai_chat_manage) via the AiChatConfig policy.
class Api::V1::Accounts::Jabvox::AiChatStoragesController < Api::V1::Accounts::BaseController
  before_action :authorize_manage
  before_action :set_storage, only: [:update, :destroy]

  def index
    render json: { storages: Current.account.jabvox_ai_chat_storages.order(:name).map { |s| serialize(s) } }
  end

  def create
    storage = Current.account.jabvox_ai_chat_storages.create!(storage_params)
    render json: serialize(storage), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @storage.update!(storage_params.except(*blank_secret_keys))
    render json: serialize(@storage)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    @storage.destroy!
    head :no_content
  end

  # POST /ai_chat_storages/test — validate credentials without saving.
  def test
    storage = Current.account.jabvox_ai_chat_storages.new(storage_params.except(*blank_secret_keys))
    render json: Jabvox::AiChatBucketService.new(storage).test_connection
  end

  private

  # Authorize against the AI Chat config policy (jabvox_ai_chat_manage / admin).
  def authorize_manage
    config = Current.account.jabvox_ai_chat_config || Current.account.build_jabvox_ai_chat_config
    authorize config, :update?
  end

  def set_storage
    @storage = Current.account.jabvox_ai_chat_storages.find(params[:id])
  end

  def blank_secret_keys
    params.dig(:storage, :secret_key).blank? ? [:secret_key] : []
  end

  def storage_params
    params.require(:storage).permit(
      :name, :bucket_name, :bucket_region, :endpoint, :access_key, :secret_key, :path_prefix
    )
  end

  def serialize(storage)
    {
      id: storage.id,
      name: storage.name,
      bucket_name: storage.bucket_name,
      bucket_region: storage.bucket_region,
      endpoint: storage.endpoint,
      access_key: storage.access_key,
      secret_key_set: storage.secret_key.present?,
      path_prefix: storage.path_prefix
    }
  end
end
