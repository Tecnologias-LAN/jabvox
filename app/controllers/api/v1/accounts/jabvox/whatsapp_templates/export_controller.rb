class Api::V1::Accounts::Jabvox::WhatsappTemplates::ExportController < Api::V1::Accounts::Jabvox::WhatsappTemplates::BaseController
  def json
    data = manager.export_json(inbox_id: params[:inbox_id])
    send_data data.to_json,
              type: 'application/json',
              disposition: "attachment; filename=whatsapp_templates_#{Current.account.id}.json"
  end

  def csv
    csv_data = manager.export_csv(inbox_id: params[:inbox_id])
    send_data csv_data,
              type: 'text/csv',
              disposition: "attachment; filename=whatsapp_templates_#{Current.account.id}.csv"
  end
end
