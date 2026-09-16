require 'csv'

# Bulk WhatsApp sends: upload a CSV (nombre, numero, template, idioma), pick the inbox it goes
# through and the user whose API token n8n will use, then dispatch it to the account's webhook.
# Also exposes the send history and the list of selectable sender users. Admin-only.
class Api::V1::Accounts::Jabvox::BulkWhatsapp::BatchesController < Api::V1::Accounts::Jabvox::BulkWhatsapp::BaseController
  include Jabvox::BulkWhatsappDeliveryStatus
  include Jabvox::BulkWhatsappReplyStatus
  include Jabvox::BulkWhatsappAnalytics

  before_action :ensure_admin

  def index
    batches = Current.account.jabvox_bulk_whatsapp_batches
                     .includes(:inbox, :sender_user, :created_by)
                     .order(created_at: :desc).limit(100)
    render json: batches.map { |b| serialize(b) }
  end

  # Reportes agregados (totales + serie por envío/día/semana); lógica en el concern.
  def analytics
    render json: analytics_report
  end

  # Detalle de una ejecución + sus destinatarios. Soporta filtro por estado,
  # búsqueda por nombre/número y export CSV (?format=csv).
  def show
    batch = Current.account.jabvox_bulk_whatsapp_batches.find(params[:id])
    scope = filtered_recipients(batch).order(:id)

    respond_to do |format|
      format.csv { send_data recipients_csv(scope), filename: "envio_#{batch.id}.csv" }
      format.json do
        recipients = scope.limit(5000).to_a
        status_map = delivery_status_map(recipients)
        reply_map = first_reply_map(recipients)
        render json: serialize(batch).merge(
          delivery_summary: delivery_summary(batch.recipients),
          recipients: recipients.map { |r| serialize_recipient(r, status_map, reply_map) }
        )
      end
    end
  end

  # Prepara un reenvío a la audiencia de un batch, opcionalmente FILTRADA por estado
  # (params[:status]: 'failed', 'sent', 'delivered', 'read', 'pending', o combinados con
  # coma). Devuelve los lead_ids de esos destinatarios + los datos del envío origen para
  # que el frontend pre-cargue el Paso 3 y reenvíe. Así "leads a enviar" nunca queda vacío.
  def reuse
    source = Current.account.jabvox_bulk_whatsapp_batches.find(params[:id])
    recipients = filtered_recipients(source)
    lead_ids = recipients.where.not(lead_id_jabvox: nil).distinct.pluck(:lead_id_jabvox)

    render json: {
      source_batch_id: source.id,
      inbox_id: source.inbox_id,
      sender_user_id: source.sender_user_id,
      mode: source.mode_jabvox,
      variable_map: source.variable_mapping_jabvox,
      template_name: source.template_name_jabvox,
      language: source.template_language_jabvox,
      lead_ids: lead_ids,
      lead_count: lead_ids.size,
      total_recipients: recipients.count,
      status_filter: params[:status]
    }
  end

  # Users of this account, for choosing whose API token is forwarded to n8n.
  # Includes each user's account role so the UI can restrict the sender to
  # administrators only (agents / custom roles are excluded in the wizard).
  def senders
    # includes(:user) + reject huérfanos (user borrado) evita nulos/NoMethodError.
    account_users = Current.account.account_users.includes(:user).select(&:user)
    render json: account_users.map { |au|
      { id: au.user_id, name: au.user.name, email: au.user.email, role: au.role }
    }
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
      response_email: params[:response_email], csv_io: file.to_io, file_name: file.original_filename,
      # La plantilla/idioma se eligen en la UI (no en el archivo). variable_map mapea
      # cada {{n}} a una columna del CSV; el service resuelve los valores por fila.
      # number_column: la columna que contiene el número (elegida/confirmada en la UI).
      # header_media: media del header de la plantilla ({ media_url, media_type }).
      # flow_button: botón FLOW de la plantilla, si tiene uno ({ index, flow_id }).
      template_name: params[:template_name], language: params[:language], text: params[:text],
      # country: de él sale el prefijo de los números del CSV que llegan sin él.
      # Opcional: sin país se conserva el comportamiento anterior.
      variable_map: variable_map_params, number_column: params[:number_column],
      header_media: header_media_params, country: params[:country],
      flow_button: flow_button_params, **extended_template_params
    )
  end

  # Tipos de plantilla adicionales soportados por Meta (carousel, authentication,
  # location, oferta por tiempo limitado, cupón). Todos son fijos para el envío
  # completo — el mapeo por columna solo aplica a las variables del cuerpo.
  # Ver docs/whatsapp-flows/templates-sending-architecture.md.
  def extended_template_params
    {
      cards: carousel_cards_params,
      auth_code: params[:auth_code].presence,
      location: location_params,
      lto_expiration_ms: params[:lto_expiration_ms].presence,
      copy_code: params[:copy_code].presence
    }.compact
  end

  # Cards de un carousel: cada una con su media de header y los parámetros de sus botones.
  def carousel_cards_params
    raw = params[:cards]
    return nil if raw.blank?

    Array(raw).filter_map do |card|
      h = card.respond_to?(:permit) ? card.permit!.to_h : card.to_h
      h.presence
    end.presence
  end

  # Header LOCATION: se completa al enviar (la plantilla aprobada no lo lleva).
  def location_params
    raw = params[:location]
    return nil if raw.blank?

    h = raw.respond_to?(:permit) ? raw.permit(:latitude, :longitude, :name, :address).to_h : raw.to_h
    h[:latitude].present? && h[:longitude].present? ? h : nil
  end

  # Media del header de la plantilla (imagen/video/documento): { media_url, media_type }.
  # Sale de la propia plantilla (el ejemplo que Meta guardó); igual para todo el envío.
  def header_media_params
    raw = params[:header_media]
    return nil if raw.blank?

    h = raw.respond_to?(:permit) ? raw.permit(:media_url, :media_type).to_h : raw.to_h
    h[:media_url].present? ? h : nil
  end

  # Botón FLOW de la plantilla ({ index, flow_id }), leído del propio JSON de la
  # plantilla por el frontend — el flow_token único por destinatario se genera en
  # el servicio, no aquí.
  def flow_button_params
    raw = params[:flow_button]
    return nil if raw.blank?

    h = raw.respond_to?(:permit) ? raw.permit(:index, :flow_id).to_h : raw.to_h
    h[:flow_id].present? ? h : nil
  end

  def dispatch_from_leads(inbox, sender)
    Jabvox::BulkWhatsappDispatchService.prepare(
      account: Current.account, inbox: inbox, sender_user: sender, actor: current_user,
      response_email: params[:response_email], leads_selection: leads_selection_params,
      template_name: params[:template_name], language: params[:language], text: params[:text],
      variable_map: variable_map_params, source_batch_id: params[:source_batch_id].presence,
      header_media: header_media_params, flow_button: flow_button_params,
      **extended_template_params
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

  # Recipients de un batch, filtrados por estado(s) y/o búsqueda (nombre/número).
  # params[:status] acepta uno o varios estados separados por coma (p. ej. "failed,pending").
  def filtered_recipients(batch)
    scope = batch.recipients
    scope = filter_by_statuses(batch.recipients, scope, params[:status]) if params[:status].present?
    if params[:q].present?
      q = "%#{params[:q].to_s.strip}%"
      scope = scope.where('name_jabvox ILIKE :q OR phone_number_jabvox ILIKE :q', q: q)
    end
    scope
  end

  def serialize_recipient(recipient, status_map = {}, reply_map = {})
    {
      id: recipient.id,
      name: recipient.name_jabvox,
      phone_number: recipient.phone_number_jabvox,
      template_name: recipient.template_name_jabvox,
      status: recipient.status_jabvox,
      error_code: recipient.error_code_jabvox,
      error_message: recipient.error_message_jabvox,
      rendered_content: recipient.rendered_content_jabvox,
      conversation_id: recipient.conversation_id,
      sent_at: recipient.sent_at_jabvox
    }.merge(recipient_delivery_fields(recipient, status_map, reply_map))
  end

  def serialize(batch)
    {
      id: batch.id, batch_uuid: batch.batch_uuid_jabvox,
      inbox_id: batch.inbox_id, inbox_name: batch.inbox&.name,
      sender_user_id: batch.sender_user_id, sender_name: batch.sender_user&.name,
      created_by_name: batch.created_by&.name, source_type: batch.source_type_jabvox,
      template_name: batch.template_name_jabvox, template_language: batch.template_language_jabvox,
      total_rows_jabvox: batch.total_rows_jabvox, valid_rows_jabvox: batch.valid_rows_jabvox,
      sent_count: batch.sent_count_jabvox, failed_count: batch.failed_count_jabvox,
      source_batch_id: batch.source_batch_id_jabvox, mode_jabvox: batch.mode_jabvox,
      status_jabvox: batch.status_jabvox, error_jabvox: batch.error_jabvox,
      file_name_jabvox: batch.file_name_jabvox, response_email_jabvox: batch.response_email_jabvox,
      sent_at_jabvox: batch.sent_at_jabvox, finished_at_jabvox: batch.finished_at_jabvox,
      token_expires_at_jabvox: batch.token_expires_at_jabvox, created_at: batch.created_at
    }
  end
end
