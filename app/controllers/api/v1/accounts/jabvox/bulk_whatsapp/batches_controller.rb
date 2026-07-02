# Bulk WhatsApp sends: upload a CSV (nombre, numero, template, idioma), pick the inbox it goes
# through and the user whose API token n8n will use, then dispatch it to the account's webhook.
# Also exposes the send history and the list of selectable sender users. Admin-only.
class Api::V1::Accounts::Jabvox::BulkWhatsapp::BatchesController < Api::V1::Accounts::Jabvox::BulkWhatsapp::BaseController
  before_action :ensure_admin

  def index
    batches = Current.account.jabvox_bulk_whatsapp_batches
                     .includes(:inbox, :sender_user, :created_by)
                     .order(created_at: :desc).limit(100)
    render json: batches.map { |b| serialize(b) }
  end

  # Users of this account, for choosing whose API token is forwarded to n8n.
  def senders
    users = Current.account.users.select(:id, :name, :email)
    render json: users.map { |u| { id: u.id, name: u.name, email: u.email } }
  end

  # The lead custom fields defined for this account, so the leads picker can offer a filter
  # per custom column (on top of the standard name/phone/country/campaign filters).
  def lead_fields
    table = Current.account.jabvox_custom_tables.for_leads.first
    columns = table ? table.jabvox_custom_columns.ordered : []
    render json: {
      custom: columns.map do |c|
        { key: c.name_jabvox, label: c.label_jabvox, column_type: c.column_type_jabvox,
          options: c.options_jabvox }
      end
    }
  end

  def create
    inbox = Current.account.inboxes.find(params[:inbox_id])
    sender = Current.account.users.find(params[:sender_user_id])

    batch = params[:source].to_s == 'leads' ? dispatch_from_leads(inbox, sender) : dispatch_from_csv(inbox, sender)
    return if performed?

    render json: serialize(batch), status: :created
  rescue Jabvox::BulkWhatsappDispatchService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def dispatch_from_csv(inbox, sender)
    file = params[:file]
    if file.blank?
      render json: { error: 'Debes adjuntar un archivo CSV.' }, status: :unprocessable_entity
      return
    end

    Jabvox::BulkWhatsappDispatchService.prepare(
      account: Current.account, inbox: inbox, sender_user: sender, actor: current_user,
      response_email: params[:response_email], csv_io: file.to_io, file_name: file.original_filename
    )
  end

  def dispatch_from_leads(inbox, sender)
    Jabvox::BulkWhatsappDispatchService.prepare(
      account: Current.account, inbox: inbox, sender_user: sender, actor: current_user,
      response_email: params[:response_email], leads_selection: leads_selection_params,
      template_name: params[:template_name], language: params[:language], text: params[:text]
    )
  end

  # Which leads to send to: either an explicit id list, or "all matching the filter" minus
  # unchecked ids. Filters mirror the leads list params.
  def leads_selection_params
    {
      all: ActiveModel::Type::Boolean.new.cast(params[:all]),
      lead_ids: Array(params[:lead_ids]),
      excluded_ids: Array(params[:excluded_ids]),
      filters: params[:filters]&.permit!.to_h
    }
  end

  def serialize(batch)
    {
      id: batch.id,
      inbox_id: batch.inbox_id,
      inbox_name: batch.inbox&.name,
      sender_user_id: batch.sender_user_id,
      sender_name: batch.sender_user&.name,
      created_by_name: batch.created_by&.name,
      total_rows_jabvox: batch.total_rows_jabvox,
      valid_rows_jabvox: batch.valid_rows_jabvox,
      mode_jabvox: batch.mode_jabvox,
      status_jabvox: batch.status_jabvox,
      error_jabvox: batch.error_jabvox,
      file_name_jabvox: batch.file_name_jabvox,
      response_email_jabvox: batch.response_email_jabvox,
      sent_at_jabvox: batch.sent_at_jabvox,
      token_expires_at_jabvox: batch.token_expires_at_jabvox,
      created_at: batch.created_at
    }
  end
end
