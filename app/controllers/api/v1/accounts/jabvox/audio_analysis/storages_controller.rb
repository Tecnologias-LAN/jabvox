class Api::V1::Accounts::Jabvox::AudioAnalysis::StoragesController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_access
  before_action :set_storage, only: [:update, :destroy, :objects]

  def index
    render json: { storages: Current.account.jabvox_audio_storages.order(:name).map { |s| serialize(s) } }
  end

  def create
    storage = Current.account.jabvox_audio_storages.create!(storage_params)
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

  # POST /storages/test — validate credentials without saving.
  def test
    storage = Current.account.jabvox_audio_storages.new(storage_params.except(*blank_secret_keys))
    render json: Jabvox::AudioBucketService.new(storage).test_connection
  end

  # GET /storages/:id/objects?prefix=&token= — browse the bucket.
  def objects
    result = Jabvox::AudioBucketService.new(@storage).list_objects(
      prefix: params[:prefix].to_s, token: params[:token]
    )
    render json: result
  end

  private

  def set_storage
    @storage = Current.account.jabvox_audio_storages.find(params[:id])
  end

  def blank_secret_keys
    params.dig(:storage, :secret_key).blank? ? [:secret_key] : []
  end

  def storage_params
    params.require(:storage).permit(
      :name, :use_documents_config, :bucket_name, :bucket_region,
      :endpoint, :access_key, :secret_key, :path_prefix
    )
  end

  def serialize(storage)
    {
      id: storage.id,
      name: storage.name,
      use_documents_config: storage.use_documents_config,
      bucket_name: storage.bucket_name,
      bucket_region: storage.bucket_region,
      endpoint: storage.endpoint,
      access_key: storage.access_key,
      secret_key_set: storage.secret_key.present?,
      path_prefix: storage.path_prefix
    }
  end
end
