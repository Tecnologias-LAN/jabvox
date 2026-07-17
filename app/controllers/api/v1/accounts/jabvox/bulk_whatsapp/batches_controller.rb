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

  # Every lead custom field the picker can filter by, ALL of them selectable.
  #
  # The field list is the UNION of:
  #   - the columns DEFINED for the account's leads table (key + label + type), and
  #   - every key actually PRESENT in the leads' custom_fields_jabvox data —
  #     covering fields created later AND definitions that drifted from the
  #     stored keys (e.g. column "seccion_c" while the data lives under "seccion").
  #
  # `options` merges the column's configured options with the distinct values
  # found across the account's leads. `truncated` tells the picker the base list
  # hit the discovery cap, so its search box should also query field_values.
  def lead_fields
    table = Current.account.jabvox_custom_tables.for_leads.first
    columns = table ? table.jabvox_custom_columns.ordered : []
    defined_keys = columns.map(&:name_jabvox)
    # Data keys that are just the "_c" variant of a defined column merge into
    # that column (values + filtering) instead of appearing as a duplicate field.
    defined_expanded = defined_keys.flat_map { |k| Jabvox::LeadCustomFilter.key_variants(k) }
    extra_keys = Jabvox::LeadCustomFilter.data_keys(Current.account) - defined_expanded
    values_by_key = Jabvox::LeadCustomFilter.distinct_values(Current.account, defined_keys + extra_keys)

    defined = columns.map do |c|
      build_field(c.name_jabvox, c.label_jabvox, c.column_type_jabvox,
                  Array(c.options_jabvox).map(&:to_s), values_by_key)
    end
    discovered_only = extra_keys.map do |key|
      build_field(key, key.tr('_', ' ').capitalize, 'text', [], values_by_key)
    end
    render json: { custom: defined + discovered_only }
  end

  # GET /batches/field_values?key=X&q=Y — server-side option search for one
  # custom field, so high-cardinality fields (base list capped at 200) can still
  # surface every value through the picker's search box.
  def field_values
    values = Jabvox::LeadCustomFilter.distinct_values_search(
      Current.account, params[:key], params[:q]
    )
    render json: { values: values }
  end

  def create
    inbox = Current.account.inboxes.find(params[:inbox_id])
    sender = Current.account.users.find(params[:sender_user_id])

    # A custom-role sender mints a token in the sender's name: only real admins
    # may send on behalf of someone else.
    unless Current.account_user&.administrator? || sender.id == current_user.id
      return render json: { error: 'Solo un administrador puede enviar en nombre de otro usuario.' },
                    status: :forbidden
    end

    batch = params[:source].to_s == 'leads' ? dispatch_from_leads(inbox, sender) : dispatch_from_csv(inbox, sender)
    return if performed?

    render json: serialize(batch), status: :created
  rescue Jabvox::BulkWhatsappDispatchService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # One selectable-field entry for the picker. `truncated` marks fields whose
  # discovered values hit the cap (200), so the frontend search also asks the
  # server (field_values) instead of trusting the partial local list.
  def build_field(key, label, column_type, configured, values_by_key)
    discovered = values_by_key[key] || []
    {
      key: key, label: label, column_type: column_type,
      options: (configured + discovered).reject(&:blank?).uniq.sort,
      truncated: discovered.size >= 200
    }
  end

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
      template_name: params[:template_name], language: params[:language], text: params[:text],
      variable_map: variable_map_params
    )
  end

  # Maps each {{n}} template placeholder to a lead field key (or "text:<literal>").
  # e.g. { "1" => "nombre", "2" => "custom:fecha_entrega2_c" }.
  def variable_map_params
    raw = params[:variable_map]
    return {} if raw.blank?

    (raw.respond_to?(:permit!) ? raw.permit!.to_h : raw.to_h)
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
