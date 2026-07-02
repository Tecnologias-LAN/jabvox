class Api::V1::Accounts::Jabvox::AiChatConfigsController < Api::V1::Accounts::BaseController
  before_action :ensure_config
  before_action :authorize_config

  def show
    render json: config_json(@config)
  end

  def update
    attrs = config_params
    # A blank secret means "keep the stored one" — don't overwrite it with empty.
    attrs = attrs.except(:bucket_secret_key_jabvox) if attrs[:bucket_secret_key_jabvox].blank?
    @config.update!(attrs)
    render json: config_json(@config)
  end

  # Folder-aware listing so the picker can navigate the bucket (folders + files
  # under a prefix), marking files already selected. Does NOT touch the DB.
  def bucket_objects
    bucket_service = Jabvox::AiChatBucketService.new(@config.documents_bucket_source)
    unless bucket_service.configured?
      return render json: { error: I18n.t('jabvox.ai_chat.documents.bucket_not_configured') },
                    status: :unprocessable_entity
    end

    result = bucket_service.browse(prefix: params[:prefix].to_s, search: params[:search].to_s)
    return render(json: { error: result[:error] }, status: :unprocessable_entity) if result[:error]

    render json: {
      folders: result[:folders],
      files: bucket_files_json(result[:files]),
      limit: Current.account.jabvox_ai_chat_max_documents_jabvox.to_i
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Persists the user's manual selection of bucket files as the active document
  # set. The account-level max is a hard cap ENFORCED here — the request is
  # rejected if it exceeds the limit, never silently truncated.
  def save_documents
    keys = Array(params[:keys]).map(&:to_s).reject(&:blank?).uniq
    max_docs = Current.account.jabvox_ai_chat_max_documents_jabvox.to_i

    if max_docs.positive? && keys.size > max_docs
      return render json: { error: I18n.t('jabvox.ai_chat.documents.limit_exceeded', limit: max_docs) },
                    status: :unprocessable_entity
    end

    synced = upsert_documents(keys)
    prune_documents(keys)

    render json: { documents: synced.map { |d| document_json(d) }, limit: max_docs }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Creates or keeps a document row for each selected key.
  def upsert_documents(keys)
    keys.map do |key|
      doc = Current.account.jabvox_ai_chat_documents.find_or_initialize_by(s3_key_jabvox: key)
      doc.assign_attributes(name_jabvox: File.basename(key)) if doc.new_record?
      doc.save!
      doc
    end
  end

  # Removes any document not in the new selection so the active set matches
  # exactly what the user chose (empty selection clears everything).
  def prune_documents(keys)
    scope = Current.account.jabvox_ai_chat_documents
    keys.empty? ? scope.destroy_all : scope.where.not(s3_key_jabvox: keys).destroy_all
  end

  # Maps bucket files to the picker's shape, flagging those already selected.
  def bucket_files_json(files)
    selected_keys = Current.account.jabvox_ai_chat_documents.pluck(:s3_key_jabvox).to_set
    files.map do |obj|
      {
        key: obj[:key],
        name: File.basename(obj[:key]),
        size: obj[:size],
        selected: selected_keys.include?(obj[:key])
      }
    end
  end

  def ensure_config
    @config = Current.account.jabvox_ai_chat_config || Current.account.create_jabvox_ai_chat_config!
  end

  def authorize_config
    authorize @config
  end

  def config_params
    params.require(:jabvox_ai_chat_config).permit(
      :bucket_url_jabvox, :bucket_access_key_jabvox, :bucket_secret_key_jabvox,
      :bucket_region_jabvox, :bucket_name_jabvox, :web_search_enabled_jabvox,
      :documents_storage_jabvox_id
    )
  end

  def config_json(c)
    {
      id: c.id,
      bucket_url_jabvox: c.bucket_url_jabvox,
      bucket_access_key_jabvox: c.bucket_access_key_jabvox,
      bucket_secret_key_jabvox: c.bucket_secret_key_jabvox.present? ? "***#{c.bucket_secret_key_jabvox.last(4)}" : nil,
      bucket_region_jabvox: c.bucket_region_jabvox,
      bucket_name_jabvox: c.bucket_name_jabvox,
      web_search_enabled_jabvox: c.web_search_enabled_jabvox,
      documents_storage_jabvox_id: c.documents_storage_jabvox_id,
      # Storages the account can point AI Chat documents at (its own, mirrored
      # from Audio Analysis by StorageSyncService).
      available_storages: Current.account.jabvox_ai_chat_storages.order(:name).map do |s|
        { id: s.id, name: s.name }
      end
    }
  end

  def document_json(d)
    { id: d.id, name_jabvox: d.name_jabvox, s3_key_jabvox: d.s3_key_jabvox, size_jabvox: d.size_jabvox, is_enabled_jabvox: d.is_enabled_jabvox }
  end
end
