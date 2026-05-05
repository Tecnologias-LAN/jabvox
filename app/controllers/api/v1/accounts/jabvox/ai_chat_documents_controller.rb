class Api::V1::Accounts::Jabvox::AiChatDocumentsController < Api::V1::Accounts::BaseController
  before_action :fetch_document, only: [:update, :destroy]
  before_action :authorize_document

  def index
    @documents = Current.account.jabvox_ai_chat_documents.ordered
    render json: @documents.map { |d| document_json(d) }
  end

  def update
    @document.update!(document_params)
    render json: document_json(@document)
  end

  def destroy
    @document.destroy!
    head :ok
  end

  private

  def fetch_document
    @document = Current.account.jabvox_ai_chat_documents.find(params[:id])
  end

  def authorize_document
    authorize @document || JabvoxAiChatDocument
  end

  def document_params
    params.require(:jabvox_ai_chat_document).permit(:name_jabvox, :is_enabled_jabvox)
  end

  def document_json(d)
    {
      id: d.id,
      name_jabvox: d.name_jabvox,
      s3_key_jabvox: d.s3_key_jabvox,
      size_jabvox: d.size_jabvox,
      is_enabled_jabvox: d.is_enabled_jabvox,
      created_at: d.created_at
    }
  end
end
