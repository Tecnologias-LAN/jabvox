class Api::V1::Accounts::Jabvox::ResponseBotDocumentsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :set_document, only: [:update, :destroy]

  def index
    authorize JabvoxResponseBotDocument
    docs = Current.account.jabvox_response_bot_documents.ordered
    render json: docs.map { |d| doc_json(d) }
  end

  def sync
    authorize JabvoxResponseBotDocument
    bucket_config = Current.account.jabvox_ai_chat_config
    return render json: { error: 'Bucket not configured' }, status: :unprocessable_entity if bucket_config&.bucket_url_jabvox.blank?

    bucket_service = Jabvox::AiChatBucketService.new(bucket_config)
    objects = bucket_service.list_objects
    synced = 0

    objects.each do |obj|
      next if obj[:key].blank?

      Current.account.jabvox_response_bot_documents.find_or_create_by!(
        s3_key_jabvox: obj[:key]
      ) do |d|
        d.name_jabvox = File.basename(obj[:key])
        d.size_jabvox = obj[:size]
        d.content_type_jabvox = obj[:content_type]
      end
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
