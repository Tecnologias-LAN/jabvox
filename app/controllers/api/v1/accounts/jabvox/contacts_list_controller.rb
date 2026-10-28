# frozen_string_literal: true

# Lista unificada de contactos: la que sustituye a la pantalla de Leads.
#
# Devuelve exactamente la misma forma que el índice de leads (filas + total + opciones de
# filtro) para que la tabla del frontend funcione igual, pero consultando `contacts`, que ya
# lleva campaña, afiliado, responsable, venta, campos personalizados y ciclo de vida.
#
# Vive aparte del ContactsController de Chatwoot a propósito: aquel sirve al núcleo (búsqueda,
# segmentos, import) y no conviene mezclarle la lógica comercial de Jabvox.
class Api::V1::Accounts::Jabvox::ContactsListController < Api::V1::Accounts::Jabvox::BaseController # rubocop:disable Metrics/ClassLength
  # Contactos es del núcleo, no un módulo: sin esto heredaba el flag por defecto
  # (`jabvox_kanban`) al retirarse el de Leads, y una cuenta sin Kanban recibía 403 al
  # abrir su propia lista de contactos. El acceso sigue acotado por rol.
  jabvox_feature :none
  include JabvoxPermissions

  PER_PAGE_OPTIONS = [25, 50, 100].freeze
  DEFAULT_PER_PAGE = 25

  def index
    scope = filter_scope
    @total = scope.count
    @contacts = scope.includes([:jabvox_campaign, :assignee, :jabvox_affiliate, company_association].compact)
                     .page(params[:page] || 1).per(per_page)
    ids = @contacts.map(&:id)
    @conv_data = conversation_data(ids)
    @management_data = management_data(ids)
    render json: {
      contacts: @contacts.map { |c| serialize(c) },
      meta: { total: @total, page: (params[:page] || 1).to_i, per_page: per_page },
      # Las opciones son estables durante la sesión y cuestan 6 consultas extra: solo se
      # mandan en la primera página, el frontend conserva su copia al paginar.
      filter_options: include_filter_options? ? filter_options : nil
    }.compact
  end

  # Cambia la etapa del ciclo de vida de un contacto (prospecto → interesado → …).
  def update_lifecycle
    contact = writable_contacts.find(params[:id])
    contact.advance_lifecycle!(params[:lifecycle_stage], by: Current.user)
    render json: serialize(contact)
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Asigna (o desasigna con assignee_id vacío) varios contactos de una vez desde la barra
  # de selección múltiple.
  def bulk_assign
    ids = Array(params[:contact_ids]).map(&:to_i).select(&:positive?)
    return render(json: { error: 'contact_ids requerido' }, status: :unprocessable_entity) if ids.empty?

    assignee = params[:assignee_id].presence
    # Se valida que el responsable pertenezca a la cuenta: un id ajeno no debe poder
    # asignarse desde el cliente.
    assignee = nil if assignee && !Current.account.users.exists?(id: assignee)
    # update_all a propósito: es una sola columna ya validada arriba y puede tocar cientos
    # de filas; cargarlas una a una para disparar callbacks haría la acción inusable.
    updated = writable_contacts.where(id: ids).update_all( # rubocop:disable Rails/SkipsModelValidations
      assignee_id: assignee, updated_at: Time.current
    )
    render json: { updated: updated, assignee_id: assignee }
  end

  # Catálogo de etapas (prospecto, interesado, cliente, inactivo). Lo consumen el formulario
  # de embudos de Kanban y cualquier selector que las ofrezca.
  def lifecycle_stages
    render json: { lifecycle_stages: Jabvox::ContactLifecycle::LIFECYCLE_STAGES.map { |s| { id: s, name: s.capitalize } } }
  end

  private

  def per_page
    PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : DEFAULT_PER_PAGE
  end

  def filter_scope
    Jabvox::ContactsFilterService.new(
      account: Current.account, user: Current.user,
      is_admin: view_all_contacts?, filters: params
    ).scope
  end

  # Los contactos sobre los que este usuario puede actuar: la MISMA regla que filtra el
  # índice. Sin esto la lista ocultaba un contacto pero sus acciones seguían aceptándolo
  # por id, así que un agente podía cambiar la etapa o reasignar contactos que no ve.
  def writable_contacts
    return Current.account.contacts if view_all_contacts?

    Current.account.contacts.visible_to(Current.account_user)
  end

  # Misma regla que tenía la lista de leads: admin o permiso explícito ve todos; el resto
  # solo los suyos.
  def view_all_contacts?
    Current.account_user&.administrator? || jabvox_can?('jabvox_contacts_view_all')
  end

  def include_filter_options?
    params[:page].blank? || params[:page].to_i <= 1 || params[:with_filter_options].present?
  end

  # Última conversación de cada contacto, para las columnas de bandeja/estado/asignado sin
  # una consulta por fila.
  def conversation_data(contact_ids)
    return {} if contact_ids.blank?

    Current.account.conversations.where(contact_id: contact_ids)
           .order(last_activity_at: :desc)
           .group_by(&:contact_id)
           .transform_values(&:first)
  end

  # Gestiones por contacto. Sin rango: la última (título y fecha). Con rango: cuántas hubo
  # y los títulos de cada una, para poder responder "cuáles tuvo entre estas fechas".
  #
  # Una gestión vive como mensaje privado con estado de gestión o como nota del contacto,
  # así que se leen ambas fuentes y se unen.
  def management_data(contact_ids)
    return {} if contact_ids.blank?

    from = parse_date(params[:date_from])
    to = parse_date(params[:date_to])
    rows = management_rows(contact_ids, from, to)
    rows.group_by { |r| r[:contact_id] }.transform_values do |list|
      sorted = list.sort_by { |r| r[:at] }.reverse
      { count: sorted.size, names: sorted.filter_map { |r| r[:name] }.uniq,
        last: sorted.first && { name: sorted.first[:name], at: sorted.first[:at] } }
    end
  end

  # Filas { contact_id, name, at } de ambas fuentes.
  def management_rows(contact_ids, from, to)
    from_messages(contact_ids, from, to) + from_notes(contact_ids, from, to)
  end

  def from_messages(contact_ids, from, to)
    convs = Current.account.conversations.where(contact_id: contact_ids)
    scope = with_management_state(Current.account.messages.where(private: true), 'messages', from, to)
    scope.joins('INNER JOIN conversations ON conversations.id = messages.conversation_id')
         .where(conversations: { id: convs.select(:id) })
         .reorder(nil)
         .pluck(Arel.sql("conversations.contact_id, #{state_name_sql('messages')}, messages.created_at"))
         .map { |cid, name, at| { contact_id: cid, name: name, at: at } }
  end

  def from_notes(contact_ids, from, to)
    return [] unless Note.column_names.include?('contact_id')

    with_management_state(Current.account.notes.where(contact_id: contact_ids), 'notes', from, to)
      .reorder(nil)
      .pluck(Arel.sql("notes.contact_id, #{state_name_sql('notes')}, notes.created_at"))
      .map { |cid, name, at| { contact_id: cid, name: name, at: at } }
  end

  def state_name_sql(table)
    "(#{table}.content_attributes #>> '{}')::json->>'jabvox_management_state_name'"
  end

  # Una gestión se reconoce porque lleva ID de estado de gestión; una nota privada normal
  # solo tiene texto.
  def with_management_state(scope, table, from, to)
    id_sql = "(#{table}.content_attributes #>> '{}')::json->>'jabvox_management_state_id'"
    scope = scope.where("#{id_sql} IS NOT NULL AND #{id_sql} <> ''")
    scope = scope.where("#{table}.created_at >= ?", from.beginning_of_day) if from
    scope = scope.where("#{table}.created_at <= ?", to.end_of_day) if to
    scope
  end

  def parse_date(value)
    value.present? ? Date.parse(value.to_s) : nil
  rescue ArgumentError, TypeError
    nil
  end

  def serialize(contact)
    {
      id: contact.id, name: contact.name, email: contact.email,
      phone_number: contact.phone_number,
      country: contact.additional_attributes&.dig('country'),
      lifecycle_stage: contact.lifecycle_stage,
      is_sold: contact.is_sold_jabvox,
      custom_fields: contact.custom_fields_jabvox,
      labels: contact.label_list,
      # Gestiones del contacto: sin rango de fechas se devuelve la ÚLTIMA (su título); con
      # rango, cuántas hubo y cuáles, que es lo que se quiere saber al acotar un periodo.
      managements: @management_data&.dig(contact.id) || { count: 0, names: [], last: nil },
      last_activity_at: contact.last_activity_at,
      created_at: contact.created_at
    }.merge(serialize_relations(contact))
  end

  # Relaciones aparte: cada una puede no existir y el `&&` mantiene el nil sin reventar.
  def serialize_relations(contact)
    conv = @conv_data&.dig(contact.id)
    {
      campaign: contact.jabvox_campaign && { id: contact.jabvox_campaign_id, name: contact.jabvox_campaign.name_jabvox },
      affiliate: contact.jabvox_affiliate && { id: contact.jabvox_affiliate_id, name: contact.jabvox_affiliate.name },
      company: company_for(contact),
      assignee: assignee_for(contact, conv),
      conversation: conv && { id: conv.id, display_id: conv.display_id, status: conv.status, inbox_id: conv.inbox_id }
    }
  end

  # Empresa (entidad) del contacto. Solo cuando el módulo está activo y el contacto tiene
  # una ligada; si no, nil (la columna muestra "—"). `respond_to?` protege de instalaciones
  # sin el modelo enterprise Company.
  def company_for(contact)
    return nil unless companies_enabled?
    return nil unless contact.respond_to?(:company) && contact.company

    { id: contact.company_id, name: contact.company.name }
  end

  def companies_enabled?
    @companies_enabled ||= Current.account.feature_enabled?('companies')
  end

  # Se incluye la asociación company en el eager-load SOLO si el módulo está activo, para no
  # intentar un JOIN a una tabla/relación que la instalación podría no tener.
  def company_association
    companies_enabled? ? :company : nil
  end

  # Responsable del contacto. Si no tiene uno propio se usa el de su conversación más
  # reciente: para el agente "quién lleva este contacto" y "quién lleva su conversación"
  # son lo mismo, y mostrar vacío cuando la conversación sí tiene dueño confunde.
  def assignee_for(contact, conv)
    return { id: contact.assignee_id, name: contact.assignee.name, source: 'contact' } if contact.assignee

    user = conv&.assignee
    user && { id: user.id, name: user.name, source: 'conversation' }
  end

  def filter_options
    {
      lifecycle_stages: Jabvox::ContactLifecycle::LIFECYCLE_STAGES.map { |s| { id: s, name: s.capitalize } },
      custom_fields: custom_field_filter_defs
    }.merge(catalog_filter_options).merge(assignment_filter_options)
  end

  # Catálogos de la cuenta que alimentan los desplegables.
  def catalog_filter_options
    {
      management_states: Current.account.jabvox_management_states.active.ordered
                                .map { |s| { id: s.name_jabvox, name: s.name_jabvox, color: s.color_jabvox } },
      campaigns: Current.account.jabvox_campaigns.ordered.map { |c| { id: c.id, name: c.name_jabvox } },
      labels: Current.account.labels.order(:title).map { |l| { id: l.title, name: l.title, color: l.color } },
      # Empresas para el filtro "Empresa": solo si el módulo está activo. Sin él, lista
      # vacía y el frontend no muestra ese filtro ni esa columna con datos.
      companies: company_filter_options
    }
  end

  # Opciones del filtro de empresa. 'none' = "Sin empresa", útil para encontrar los contactos
  # que aún no se han ligado a ninguna. Vacío si el módulo está apagado.
  def company_filter_options
    return [] unless companies_enabled?

    [{ id: 'none', name: I18n.t('jabvox.contacts.no_company', default: 'Sin empresa') }] +
      Current.account.companies.order(:name).map { |c| { id: c.id, name: c.name } }
  end

  # Campos personalizados del contacto como filtros SELECCIONABLES: cada uno ofrece las
  # opciones configuradas más los valores que realmente existen en la cuenta, para que el
  # agente elija en vez de teclear un valor que quizá no exista.
  def custom_field_filter_defs
    table = Current.account.jabvox_custom_tables.for_contacts.first
    return [] unless table

    columns = table.jabvox_custom_columns.ordered
    values_by_key = Jabvox::LeadCustomFilter.distinct_values(Current.account, columns.map(&:name_jabvox))
    columns.map { |c| custom_field_def(c, values_by_key[c.name_jabvox]) }
  end

  # Las opciones combinan las configuradas en la columna con los valores que de verdad
  # existen en la cuenta, para que el filtro no ofrezca opciones vacías ni omita las que
  # llegaron por importación.
  def custom_field_def(column, discovered)
    options = Array(column.options_jabvox).map(&:to_s) + Array(discovered)
    { key: column.name_jabvox,
      label: column.label_jabvox.presence || column.name_jabvox,
      column_type: column.column_type_jabvox,
      options: options.reject(&:blank?).uniq.sort }
  end

  # Opciones que dependen de la estructura de la cuenta (a quién se puede asignar y por
  # dónde entra el contacto), separadas para que cada método quede legible.
  def assignment_filter_options
    {
      inboxes: Current.account.inboxes.order(:name).map { |i| { id: i.id, name: i.name } },
      teams: Current.account.teams.order(:name).map { |t| { id: t.id, name: t.name } },
      assignees: Current.account.users.order(:name).map { |a| { id: a.id, name: a.name } },
      affiliates: Current.account.jabvox_affiliates.where(active: true).order(:name)
                         .map { |a| { id: a.id, name: a.name } }
    }
  end
end
