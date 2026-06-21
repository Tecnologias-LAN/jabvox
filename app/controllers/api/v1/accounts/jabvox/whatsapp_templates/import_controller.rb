class Api::V1::Accounts::Jabvox::WhatsappTemplates::ImportController < Api::V1::Accounts::Jabvox::WhatsappTemplates::BaseController
  def create
    inbox = Current.account.inboxes.find(params.require(:inbox_id))
    raw = params[:templates]
    raw = JSON.parse(params[:file].read) if raw.blank? && params[:file].present?
    result = manager.import_json(inbox, raw)
    render json: result
  rescue JSON::ParserError => e
    render json: { error: "JSON inválido: #{e.message}" }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
