# Informes → Plantillas: cross-account history of every WhatsApp template send —
# from a bulk batch (JabvoxBulkWhatsappRecipient) AND from an agent sending a
# template 1-a-1 from a conversation (a Message with template_params) — a lead
# answering the same template twice, once from each origin, shows both rows on
# purpose (see Jabvox::TemplateSendRow, the adapter both sources go through).
# Read-only; reuses the same delivered/read/replied resolution as the per-batch
# report so both views never disagree about what "replied" means.
class Api::V1::Accounts::Jabvox::BulkWhatsapp::TemplatesReportController < Api::V1::Accounts::Jabvox::BulkWhatsapp::BaseController
  include Jabvox::BulkWhatsappDeliveryStatus
  include Jabvox::BulkWhatsappReplyStatus

  before_action :ensure_admin

  PER_PAGE = 50

  def show
    rows = filtered_rows

    respond_to do |format|
      format.csv do
        send_data recipients_csv(rows.sort_by { |r| r.sent_at_jabvox || Time.zone.at(0) }.reverse, with_origin: true),
                  filename: 'plantillas_whatsapp.csv'
      end
      format.json { render json: json_response(rows) }
    end
  end

  private

  def json_response(rows)
    sorted = rows.sort_by { |r| r.sent_at_jabvox || Time.zone.at(0) }.reverse
    page = [params[:page].to_i, 1].max
    page_rows = sorted.slice((page - 1) * PER_PAGE, PER_PAGE) || []
    status_map = delivery_status_map(page_rows)
    reply_map = first_reply_map(page_rows)
    {
      delivery_summary: array_delivery_summary(rows),
      total: rows.size,
      page: page,
      per_page: PER_PAGE,
      recipients: page_rows.map { |r| serialize_recipient(r, status_map, reply_map) },
      templates: filter_options_templates,
      inboxes: filter_options_inboxes
    }
  end

  # Every send attempt across BOTH origins, already matching the date/template/
  # inbox/search filters — status (delivered/read/replied/not_replied) is
  # filtered afterwards, in Ruby, since it needs first_reply_map/delivery_status_map
  # (array-friendly) rather than a SQL scope once the two sources are merged.
  def filtered_rows
    rows = bulk_rows + individual_rows
    rows = filter_rows_by_statuses(rows, params[:status]) if params[:status].present?
    rows
  end

  def bulk_rows
    scope = JabvoxBulkWhatsappRecipient.where(account_id: Current.account.id).where.not(sent_at_jabvox: nil)
    scope = filter_bulk_by_date(scope)
    scope = scope.where(template_name_jabvox: params[:template]) if params[:template].present?
    scope = filter_bulk_by_inbox(scope)
    scope = filter_by_search(scope, :name_jabvox, :phone_number_jabvox) if params[:q].present?
    scope.map { |r| Jabvox::TemplateSendRow.from_bulk_recipient(r) }
  end

  def filter_bulk_by_date(scope)
    scope = scope.where('sent_at_jabvox >= ?', Time.zone.at(params[:from].to_i)) if params[:from].present?
    scope = scope.where('sent_at_jabvox <= ?', Time.zone.at(params[:to].to_i)) if params[:to].present?
    scope
  end

  # Recipients don't carry inbox_id directly — join through the batch, which does
  # (a batch always sends through one inbox).
  def filter_bulk_by_inbox(scope)
    return scope if params[:inbox_id].blank?

    scope.where(bulk_whatsapp_batch_id: Current.account.jabvox_bulk_whatsapp_batches.where(inbox_id: params[:inbox_id]).select(:id))
  end

  TEMPLATE_NAME_SQL = "additional_attributes -> 'template_params' ->> 'name'".freeze

  def individual_template_messages
    scope = Current.account.messages.where(message_type: %i[outgoing template], private: false)
                   .where("#{TEMPLATE_NAME_SQL} IS NOT NULL")
    scope = filter_messages_by_date(scope)
    scope = scope.where("#{TEMPLATE_NAME_SQL} = ?", params[:template]) if params[:template].present?
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    scope
  end

  def filter_messages_by_date(scope)
    scope = scope.where('messages.created_at >= ?', Time.zone.at(params[:from].to_i)) if params[:from].present?
    scope = scope.where('messages.created_at <= ?', Time.zone.at(params[:to].to_i)) if params[:to].present?
    scope
  end

  def individual_rows
    messages = individual_template_messages.to_a
    return [] if messages.empty?

    contacts = contacts_for(messages.map(&:conversation_id))
    messages = filter_messages_by_search(messages, contacts) if params[:q].present?
    messages.map do |m|
      contact = contacts[m.conversation_id] || {}
      Jabvox::TemplateSendRow.from_message(m, contact_name: contact[:name], contact_phone: contact[:phone])
    end
  end

  # { conversation_id => { name:, phone: } } in one query — same pattern as
  # V2::Reports::WhatsappReport::AgentDetail#contacts_for.
  def contacts_for(conversation_ids)
    ids = conversation_ids.compact.uniq
    return {} if ids.empty?

    Current.account.conversations.where(id: ids).joins(:contact)
           .pluck('conversations.id', 'contacts.name', 'contacts.phone_number')
           .to_h { |cid, name, phone| [cid, { name: name, phone: phone }] }
  end

  def filter_by_search(scope, *columns)
    q = "%#{params[:q].to_s.strip}%"
    conditions = columns.map { |c| "#{c} ILIKE :q" }.join(' OR ')
    scope.where(conditions, q: q)
  end

  def filter_messages_by_search(messages, contacts)
    q = params[:q].to_s.strip.downcase
    messages.select do |m|
      contact = contacts[m.conversation_id] || {}
      contact[:name].to_s.downcase.include?(q) || contact[:phone].to_s.downcase.include?(q)
    end
  end

  def array_delivery_summary(rows)
    status_map = delivery_status_map(rows)
    delivered = rows.count { |r| status_map[r.chatwoot_message_id]&.key?('delivered') }
    read = rows.count { |r| status_map[r.chatwoot_message_id]&.key?('read') }
    replied = first_reply_map(rows.select { |r| r.conversation_id && r.sent_at_jabvox }).size
    { delivered: delivered, read: read, replied: replied }
  end

  def filter_rows_by_statuses(rows, status_param)
    statuses = status_param.to_s.split(',').map(&:strip).reject(&:blank?).uniq
    return rows if statuses.empty?

    statuses.flat_map { |st| rows_matching_status(rows, st) }.uniq
  end

  def rows_matching_status(rows, status)
    case status
    when 'replied', 'not_replied' then rows_matching_reply_status(rows, status)
    when 'delivered', 'read' then rows_matching_delivery_status(rows, status)
    else rows.select { |r| r.status_jabvox == status }
    end
  end

  def rows_matching_reply_status(rows, status)
    replied_ids = first_reply_map(rows.select { |r| r.conversation_id && r.sent_at_jabvox }).keys
    status == 'replied' ? rows.select { |r| replied_ids.include?(r.id) } : rows.reject { |r| replied_ids.include?(r.id) }
  end

  def rows_matching_delivery_status(rows, status)
    status_map = delivery_status_map(rows)
    rows.select { |r| status_map[r.chatwoot_message_id]&.key?(status) }
  end

  # Every template name ever sent (both origins), for the filter dropdown —
  # capped so a runaway number of ad-hoc template names can't blow up the response.
  def filter_options_templates
    from_bulk = JabvoxBulkWhatsappRecipient.where(account_id: Current.account.id)
                                           .where.not(template_name_jabvox: [nil, ''])
                                           .distinct.pluck(:template_name_jabvox)
    from_messages = Current.account.messages.where(message_type: %i[outgoing template])
                           .where("#{TEMPLATE_NAME_SQL} IS NOT NULL")
                           .pluck(Arel.sql(TEMPLATE_NAME_SQL))
    (from_bulk + from_messages).compact_blank.uniq.sort.first(200)
  end

  def filter_options_inboxes
    Current.account.inboxes.where(channel_type: 'Channel::Whatsapp').order(:name).pluck(:id, :name)
           .map { |id, name| { id: id, name: name } }
  end

  def serialize_recipient(row, status_map, reply_map)
    {
      id: row.id,
      name: row.name_jabvox,
      phone_number: row.phone_number_jabvox,
      template_name: row.template_name_jabvox,
      status: row.status_jabvox,
      error_code: row.error_code_jabvox,
      error_message: row.error_message_jabvox,
      sent_at: row.sent_at_jabvox,
      origin: row.source
    }.merge(recipient_delivery_fields(row, status_map, reply_map))
  end
end
