# Informes → Plantillas: cross-batch history of every WhatsApp template send
# for the account (not one batch at a time, like BatchesController#show).
# Read-only; reuses the same delivered/read/replied resolution as the
# per-batch report so both views never disagree about what "replied" means.
class Api::V1::Accounts::Jabvox::BulkWhatsapp::TemplatesReportController < Api::V1::Accounts::Jabvox::BulkWhatsapp::BaseController
  include Jabvox::BulkWhatsappDeliveryStatus
  include Jabvox::BulkWhatsappReplyStatus

  before_action :ensure_admin

  PER_PAGE = 50

  def show
    scope = filtered_recipients

    respond_to do |format|
      format.csv { send_data recipients_csv(scope.order(sent_at_jabvox: :desc)), filename: 'plantillas_whatsapp.csv' }
      format.json { render json: json_response(scope) }
    end
  end

  private

  def json_response(scope)
    page = [params[:page].to_i, 1].max
    recipients = scope.order(sent_at_jabvox: :desc).offset((page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    status_map = delivery_status_map(recipients)
    reply_map = first_reply_map(recipients)
    {
      delivery_summary: delivery_summary(scope),
      total: scope.count,
      page: page,
      per_page: PER_PAGE,
      recipients: recipients.map { |r| serialize_recipient(r, status_map, reply_map) },
      templates: filter_options_templates,
      inboxes: filter_options_inboxes
    }
  end

  # Base universe: every recipient of a REAL send attempt (has sent_at_jabvox)
  # across every batch of this account — a batch still 'pending'/'draft'
  # (nothing dispatched yet) contributes nothing here on purpose.
  def base_recipients
    JabvoxBulkWhatsappRecipient
      .where(account_id: Current.account.id)
      .where.not(sent_at_jabvox: nil)
  end

  def filtered_recipients
    scope = base_recipients
    scope = filter_by_date_range(scope)
    scope = scope.where(template_name_jabvox: params[:template]) if params[:template].present?
    scope = filter_by_inbox(scope)
    scope = filter_by_statuses(base_recipients, scope, params[:status]) if params[:status].present?
    if params[:q].present?
      q = "%#{params[:q].to_s.strip}%"
      scope = scope.where('name_jabvox ILIKE :q OR phone_number_jabvox ILIKE :q', q: q)
    end
    scope
  end

  def filter_by_date_range(scope)
    scope = scope.where('sent_at_jabvox >= ?', Time.zone.at(params[:from].to_i)) if params[:from].present?
    scope = scope.where('sent_at_jabvox <= ?', Time.zone.at(params[:to].to_i)) if params[:to].present?
    scope
  end

  # Recipients don't carry inbox_id directly — join through the batch, which
  # does (a batch always sends through one inbox).
  def filter_by_inbox(scope)
    return scope if params[:inbox_id].blank?

    scope.where(bulk_whatsapp_batch_id: Current.account.jabvox_bulk_whatsapp_batches.where(inbox_id: params[:inbox_id]).select(:id))
  end

  # Every template name ever sent, for the filter dropdown — capped so a
  # runaway number of ad-hoc template names can't blow up the response.
  def filter_options_templates
    base_recipients.distinct.order(:template_name_jabvox).limit(200).pluck(:template_name_jabvox).compact_blank
  end

  def filter_options_inboxes
    Current.account.jabvox_bulk_whatsapp_batches
           .joins(:inbox).distinct.pluck('inboxes.id', 'inboxes.name')
           .map { |id, name| { id: id, name: name } }
  end

  def serialize_recipient(recipient, status_map, reply_map)
    {
      id: recipient.id,
      batch_id: recipient.bulk_whatsapp_batch_id,
      name: recipient.name_jabvox,
      phone_number: recipient.phone_number_jabvox,
      template_name: recipient.template_name_jabvox,
      status: recipient.status_jabvox,
      error_code: recipient.error_code_jabvox,
      error_message: recipient.error_message_jabvox,
      sent_at: recipient.sent_at_jabvox
    }.merge(recipient_delivery_fields(recipient, status_map, reply_map))
  end
end
