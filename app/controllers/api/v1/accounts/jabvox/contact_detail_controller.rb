# frozen_string_literal: true

# Detalle completo de UN contacto para la pantalla unificada: sus conversaciones por bandeja,
# gestiones, productos/pedidos y registros de actividad.
#
# Sustituye a lo que antes daba el detalle de lead. Todo cuelga del contacto, que ya lleva
# campaña, afiliado, responsable, etapa del ciclo de vida y campos personalizados.
class Api::V1::Accounts::Jabvox::ContactDetailController < Api::V1::Accounts::Jabvox::BaseController
  # Contactos es del núcleo, no un módulo: sin esto heredaba el flag por defecto
  # (`jabvox_kanban`) al retirarse el de Leads, y una cuenta sin Kanban recibía 403 al
  # abrir su propia lista de contactos. El acceso sigue acotado por rol.
  jabvox_feature :none
  include JabvoxPermissions

  MAX_ROWS = 50

  def show
    contact = find_contact
    render json: {
      contact: contact_view(contact),
      conversations: conversations_for(contact),
      managements: managements_for(contact),
      orders: orders_for(contact),
      records: records_for(contact),
      custom_field_defs: custom_field_defs,
      management_states: catalog.management_states,
      lifecycle_stages: Jabvox::ContactLifecycle::LIFECYCLE_STAGES.map { |s| { id: s, name: s.capitalize } }
    }
  end

  # Secciones sueltas, para recargar solo una pestaña sin volver a pedirlo todo.
  def managements
    render json: { managements: managements_for(find_contact) }
  end

  def orders
    render json: { orders: orders_for(find_contact) }
  end

  def records
    render json: { records: records_for(find_contact) }
  end

  # Campos personalizados, etapa del ciclo de vida y responsable. Van por separado del
  # update normal de contacto porque son columnas propias de Jabvox que el serializador de
  # Chatwoot no toca.
  def update_custom_fields
    contact = find_contact
    # La etapa primero: `advance_lifecycle!` reescribe `custom_fields_jabvox` para añadir su
    # historial, así que hacerlo después pisaría los campos recién guardados.
    contact.advance_lifecycle!(params[:lifecycle_stage], by: Current.user) if lifecycle_change?(contact)
    contact.update!(custom_fields_jabvox: merged_custom_fields(contact), **assignee_change)
    render json: { contact: contact_view(contact.reload) }
  rescue Jabvox::CustomFieldsCoercion::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Nueva gestión desde la ficha. Se guarda como nota del contacto —no como mensaje— porque
  # la gestión pertenece al contacto, no a una conversación concreta: el contacto puede
  # tener varias bandejas abiertas o ninguna.
  def create_management
    contact = find_contact
    note = Current.account.notes.create!(
      contact: contact,
      user: Current.user,
      content: management_content,
      content_attributes: management_attributes
    )
    render json: { management: management_row(note, 'note') }, status: :created
  end

  private

  # El responsable solo se toca si el cliente manda la clave: así, no mandarla deja el
  # asignado como está en vez de desasignarlo por omisión. Mandarla vacía SÍ desasigna.
  # El id se valida contra los usuarios de la cuenta, nunca se asigna a alguien de fuera.
  def assignee_change
    return {} unless params.key?(:assignee_id)

    raw = params[:assignee_id]
    return { assignee_id: nil } if raw.blank?

    { assignee_id: Current.account.users.find(raw).id }
  end

  def lifecycle_change?(contact)
    stage = params[:lifecycle_stage].to_s
    stage.present? && stage != contact.lifecycle_stage &&
      Jabvox::ContactLifecycle::LIFECYCLE_STAGES.include?(stage)
  end

  # La conversión por tipo vive en su propio objeto: es lógica de dominio (qué es una fecha
  # válida, qué opciones admite un select), no de transporte.
  def merged_custom_fields(contact)
    Jabvox::CustomFieldsCoercion
      .new(Current.account)
      .merge_into(contact.custom_fields_jabvox, params[:custom_fields])
  end

  def management_content
    content = params[:content].to_s.strip
    content.presence || params.dig(:content_attributes, :jabvox_management_state_name).to_s
  end

  def management_attributes
    Jabvox::ManagementPayload.new(params[:content_attributes]).to_h
  end

  def catalog
    @catalog ||= Jabvox::ContactFormCatalog.new(Current.account)
  end

  def custom_field_defs
    catalog.custom_field_defs
  end

  # `visible_to` aplica la misma restricción por rol que la lista de contactos: un admin ve
  # todo; un agente solo los contactos que tiene asignados o con los que le une una
  # conversación suya. Sin esto el scope era solo de cuenta, así que un agente podía leer
  # por URL el detalle completo —conversaciones, gestiones, pedidos y registros— de un
  # contacto que la lista le oculta.
  def find_contact
    Current.account.contacts
           .visible_to(Current.account_user)
           .includes(:jabvox_campaign, :jabvox_affiliate, :assignee)
           .find(params[:id])
  end

  def contact_view(contact)
    {
      id: contact.id, name: contact.name, email: contact.email,
      phone_number: contact.phone_number, identifier: contact.identifier,
      additional_attributes: contact.additional_attributes,
      custom_attributes: contact.custom_attributes,
      custom_fields: contact.custom_fields_jabvox,
      lifecycle_stage: contact.lifecycle_stage,
      is_sold: contact.is_sold_jabvox,
      labels: contact.label_list,
      campaign: contact.jabvox_campaign && { id: contact.jabvox_campaign_id, name: contact.jabvox_campaign.name_jabvox },
      affiliate: contact.jabvox_affiliate && { id: contact.jabvox_affiliate_id, name: contact.jabvox_affiliate.name },
      assignee: contact.assignee && { id: contact.assignee_id, name: contact.assignee.name },
      created_at: contact.created_at, last_activity_at: contact.last_activity_at
    }
  end

  # Una entrada por CONVERSACIÓN, agrupables por bandeja en el frontend: el contacto puede
  # haber escrito por WhatsApp y por Facebook, y cada canal es una conversación distinta.
  def conversations_for(contact)
    Current.account.conversations
           .where(contact_id: contact.id)
           .includes(:inbox, :assignee)
           .order(last_activity_at: :desc)
           .limit(MAX_ROWS)
           .map do |conv|
      { id: conv.id, display_id: conv.display_id, status: conv.status,
        inbox: conv.inbox && { id: conv.inbox_id, name: conv.inbox.name, channel_type: conv.inbox.channel_type },
        assignee: conv.assignee && { id: conv.assignee_id, name: conv.assignee.name },
        unread_count: conv.unread_incoming_messages.count,
        last_activity_at: conv.last_activity_at, created_at: conv.created_at }
    end
  end

  # Gestiones: viven como mensaje privado con estado de gestión o como nota del contacto.
  # Se unen ambas fuentes y se ordenan por fecha, que es como las lee un agente.
  def managements_for(contact)
    rows = managements_from_messages(contact) + managements_from_notes(contact)
    rows.sort_by { |r| r[:created_at] }.reverse.first(MAX_ROWS)
  end

  def managements_from_messages(contact)
    conv_ids = Current.account.conversations.where(contact_id: contact.id).select(:id)
    Current.account.messages
           .where(private: true, conversation_id: conv_ids)
           .where("#{state_id_sql('messages')} IS NOT NULL AND #{state_id_sql('messages')} <> ''")
           .order(created_at: :desc).limit(MAX_ROWS)
           .map { |m| management_row(m, 'conversation') }
  end

  def managements_from_notes(contact)
    return [] unless Note.column_names.include?('contact_id')

    Current.account.notes
           .where(contact_id: contact.id)
           .where("#{state_id_sql('notes')} IS NOT NULL AND #{state_id_sql('notes')} <> ''")
           .order(created_at: :desc).limit(MAX_ROWS)
           .map { |n| management_row(n, 'note') }
  end

  def management_row(record, source)
    attrs = parsed_attributes(record)
    { id: record.id, source: source,
      state_name: attrs['jabvox_management_state_name'],
      state_id: attrs['jabvox_management_state_id'],
      content: record.content.to_s.first(500),
      answers: attrs['jabvox_management_answers'],
      user: record.try(:user)&.name || record.try(:sender)&.name,
      created_at: record.created_at }
  end

  # content_attributes puede llegar como Hash o como JSON en texto según el origen.
  def parsed_attributes(record)
    raw = record.content_attributes
    return raw if raw.is_a?(Hash)

    JSON.parse(raw.to_s)
  rescue JSON::ParserError, TypeError
    {}
  end

  def state_id_sql(table)
    "(#{table}.content_attributes #>> '{}')::json->>'jabvox_management_state_id'"
  end

  # Pedidos y cotizaciones del contacto.
  def orders_for(contact)
    return [] unless Current.account.respond_to?(:jabvox_orders)

    Current.account.jabvox_orders
           .where(contact_id: contact.id)
           .order(created_at: :desc).limit(MAX_ROWS)
           .map { |o| order_view(o) }
  end

  def order_view(order)
    { id: order.id, doc_type: order.doc_type, status: order.status,
      total: order.total&.to_s, subtotal: order.subtotal&.to_s,
      alegra_number: order.try(:alegra_number), notes: order.try(:notes),
      created_at: order.created_at }
  end

  # Registros: las filas de las tablas personalizadas de VARIAS filas (Asesorías, Casos…)
  # ligadas al contacto. Cada tabla llega con sus columnas para que el frontend pueda
  # pintarlas y editarlas sin pedir el esquema por separado.
  #
  # No confundir con los campos personalizados de la izquierda: ésos son la tabla `single`,
  # una sola fila por contacto. Aquí un contacto puede tener muchas filas por tabla.
  def records_for(contact)
    catalog.record_tables_for(contact, limit: MAX_ROWS)
  end
end
