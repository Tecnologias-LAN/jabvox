class Api::V1::Accounts::Jabvox::ResponseBotDocumentsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  before_action :ensure_module_permission
  before_action :set_document, only: [:update, :destroy]

  def index
    authorize JabvoxResponseBotDocument
    docs = Current.account.jabvox_response_bot_documents.ordered
    render json: docs.map { |d| doc_json(d) }
  end

  def sync
    authorize JabvoxResponseBotDocument
    bucket_service = documents_bucket_service
    return render(json: { error: 'Bucket not configured' }, status: :unprocessable_entity) unless bucket_service

    synced = 0
    bucket_service.list_objects.each do |obj|
      next if obj[:key].blank?

      upsert_response_bot_document(obj)
      synced += 1
    end

    render json: { synced: synced }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    authorize @document
    @document.update!(document_params)
    render json: doc_json(@document)
  end

  def destroy
    authorize @document
    @document.destroy!
    head :no_content
  end

  private

  # Bucket service for the account's document source (shared storage or the
  # inline AI Chat bucket). Returns nil when nothing usable is configured.
  def documents_bucket_service
    config = Current.account.jabvox_ai_chat_config
    service = Jabvox::AiChatBucketService.new(config&.documents_bucket_source)
    service.configured? ? service : nil
  end

  def upsert_response_bot_document(obj)
    Current.account.jabvox_response_bot_documents.find_or_create_by!(s3_key_jabvox: obj[:key]) do |d|
      d.name_jabvox = File.basename(obj[:key])
      d.size_jabvox = obj[:size]
      d.content_type_jabvox = obj[:content_type]
    end
  end

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    return if Current.account_user&.custom_role.nil?

    jabvox_authorize!('jabvox_response_bot_manage')
  end

  def set_document
    @document = Current.account.jabvox_response_bot_documents.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:enabled_jabvox, :label_category_jabvox, :name_jabvox)
  end

  def doc_json(doc)
    {
      id: doc.id,
      name_jabvox: doc.name_jabvox,
      s3_key_jabvox: doc.s3_key_jabvox,
      size_jabvox: doc.size_jabvox,
      label_category_jabvox: doc.label_category_jabvox,
      enabled_jabvox: doc.enabled_jabvox
    }
  end
end
