class Api::V1::Accounts::Jabvox::AiChatConfigsController < Api::V1::Accounts::BaseController
  before_action :ensure_config
  before_action :authorize_config

  def show
    render json: config_json(@config)
  end

  def update
    @config.update!(config_params)
    render json: config_json(@config)
  end

  def sync_documents
    authorize @config, :sync_documents?
    bucket_service = Jabvox::AiChatBucketService.new(@config)
    objects = bucket_service.list_objects

    synced = objects.map do |obj|
      doc = Current.account.jabvox_ai_chat_documents.find_or_initialize_by(s3_key_jabvox: obj[:key])
      doc.assign_attributes(name_jabvox: File.basename(obj[:key]), size_jabvox: obj[:size])
      doc.save!
      doc
    end

    # Check document limit
    max_docs = Current.account.jabvox_ai_chat_max_documents_jabvox
    if max_docs > 0 && synced.count > max_docs
      render json: { error: "Se excede el límite de #{max_docs} documentos permitidos." }, status: :unprocessable_entity
      return
    end

    render json: synced.map { |d| document_json(d) }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_config
    @config = Current.account.jabvox_ai_chat_config || Current.account.create_jabvox_ai_chat_config!
  end

  def authorize_config
    authorize @config
  end

  def config_params
    params.require(:jabvox_ai_chat_config).permit(:bucket_url_jabvox, :bucket_access_key_jabvox, :bucket_secret_key_jabvox, :bucket_region_jabvox, :bucket_name_jabvox, :web_search_enabled_jabvox)
  end

  def config_json(c)
    {
      id: c.id,
      bucket_url_jabvox: c.bucket_url_jabvox,
      bucket_access_key_jabvox: c.bucket_access_key_jabvox,
      bucket_secret_key_jabvox: c.bucket_secret_key_jabvox.present? ? "***#{c.bucket_secret_key_jabvox.last(4)}" : nil,
      bucket_region_jabvox: c.bucket_region_jabvox,
      bucket_name_jabvox: c.bucket_name_jabvox,
      web_search_enabled_jabvox: c.web_search_enabled_jabvox
    }
  end

  def document_json(d)
    { id: d.id, name_jabvox: d.name_jabvox, s3_key_jabvox: d.s3_key_jabvox, size_jabvox: d.size_jabvox, is_enabled_jabvox: d.is_enabled_jabvox }
  end
end
