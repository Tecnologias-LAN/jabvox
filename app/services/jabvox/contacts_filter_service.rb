# frozen_string_literal: true

# Filtra y ordena contactos para la pantalla unificada, la que sustituye a la de Leads.
#
# Acepta los MISMOS filtros que aceptaba LeadsFilterService (q, email, phone, document,
# country, campaign_id, sold, affiliate_id, inbox_id, assignee_id, team_id, status,
# management_state, date_from/to, custom, sort) más `lifecycle_stage`, que es el que
# sustituye a la distinción "es lead / no es lead".
#
# La diferencia con el servicio viejo es de dónde cuelga la consulta: antes partía de
# la tabla de leads y hacía join al contacto; ahora parte del contacto, que ya lleva campaña,
# afiliado, responsable, venta y campos personalizados. Los filtros de conversación,
# gestiones y ventas ya trabajaban con contact_id, así que se conservan tal cual.
class Jabvox::ContactsFilterService
  SORTABLE_COLUMNS = {
    'created_at' => 'contacts.created_at',
    'name' => 'contacts.name',
    'last_activity_at' => 'contacts.last_activity_at',
    'lifecycle_stage' => 'contacts.lifecycle_stage_jabvox'
  }.freeze

  # Mismas claves que el filtro de documento del detalle y del dialer.
  DOCUMENT_CUSTOM_KEYS = %w[documento documento_c document cedula cedula_c dni nit
                            identificacion identificacion_c].freeze

  def initialize(account:, user:, is_admin:, filters: {})
    @account = account
    @user = user
    @is_admin = is_admin
    raw = filters || {}
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    @filters = raw.with_indifferent_access
  end

  def scope
    contacts = base_scope
    contacts = apply_text_filters(contacts)
    contacts = apply_commercial_filters(contacts)
    contacts = apply_conversation_filters(contacts)
    contacts = apply_management_filters(contacts)
    contacts = Jabvox::LeadCustomFilter.apply(contacts, @filters[:custom])
    contacts.order(order_clause)
  end

  private

  def base_scope
    scope = @account.contacts
    # `@is_admin` es en realidad "puede ver todos": el resto solo ve los suyos, la misma
    # regla que aplicaba la lista de leads y el kanban.
    scope = scope.where(assignee_id: @user.id) unless @is_admin
    scope = scope.where(id: @filters[:contact_id]) if @filters[:contact_id].present?
    # `contact_ids` lo usa la tabla para enriquecer SOLO las filas visibles en una consulta,
    # en vez de una por fila.
    scope = scope.where(id: Array(@filters[:contact_ids])) if @filters[:contact_ids].present?
    scope
  end

  def apply_text_filters(scope)
    scope = scope.where('contacts.name ILIKE ?', "%#{like(@filters[:q])}%") if @filters[:q].present?
    scope = scope.where('contacts.email ILIKE ?', "%#{like(@filters[:email])}%") if @filters[:email].present?
    scope = scope.where('contacts.phone_number ILIKE ?', "%#{like(@filters[:phone])}%") if @filters[:phone].present?
    scope = scope.where("contacts.additional_attributes->>'country' ILIKE ?", "%#{like(@filters[:country])}%") if @filters[:country].present?
    apply_document_filter(scope)
  end

  def apply_commercial_filters(scope)
    # Los filtros de selección aceptan UNO o VARIOS valores: `where` con un array genera
    # un IN, así que el mismo código sirve para ambos casos.
    scope = scope.where(lifecycle_stage_jabvox: Array(@filters[:lifecycle_stage])) if @filters[:lifecycle_stage].present?
    scope = scope.where(jabvox_campaign_id: Array(@filters[:campaign_id])) if @filters[:campaign_id].present?
    scope = apply_company_filter(scope)
    scope = apply_label_filter(scope)
    scope = apply_sold_filter(scope)
    apply_affiliate_filter(scope)
  end

  # Filtro por EMPRESA (entidad). Solo si el módulo companies está activo; con él apagado
  # no existe company_id útil, así que se ignora para no filtrar por una columna sin datos.
  # Acepta uno o varios ids (IN). El valor 'none' trae los contactos SIN empresa.
  def apply_company_filter(scope)
    return scope unless @account.feature_enabled?('companies')

    values = Array(@filters[:company_id]).reject(&:blank?)
    return scope if values.empty?

    if values.include?('none')
      ids = values.reject { |v| v == 'none' }
      ids.any? ? scope.where('contacts.company_id IN (?) OR contacts.company_id IS NULL', ids) : scope.where(company_id: nil)
    else
      scope.where(company_id: values)
    end
  end

  # Contactos que tengan CUALQUIERA de las etiquetas pedidas.
  def apply_label_filter(scope)
    labels = Array(@filters[:labels]).reject(&:blank?)
    return scope if labels.empty?

    tagged = ActsAsTaggableOn::Tagging
             .joins(:tag)
             .where(taggable_type: 'Contact', context: 'labels', tags: { name: labels })
             .select(:taggable_id)
    scope.where(id: tagged)
  end

  # El documento puede vivir en tres sitios distintos según cómo entró el contacto.
  def apply_document_filter(scope)
    return scope if @filters[:document].blank?

    doc = "%#{like(@filters[:document])}%"
    custom = DOCUMENT_CUSTOM_KEYS.map { |k| "contacts.custom_fields_jabvox->>'#{k}' ILIKE :d" }
    scope.where(
      "contacts.additional_attributes->>'jabvox_identification_number' ILIKE :d " \
      "OR contacts.identifier ILIKE :d OR #{custom.join(' OR ')}", d: doc
    )
  end

  def apply_sold_filter(scope)
    return scope if @filters[:sold].blank?

    orders = @account.jabvox_orders.where.not(contact_id: nil)
    orders = orders.where(doc_type: 'QUOTE') if @filters[:sold] == 'quotes'
    orders = orders.where(doc_type: 'SALE') if @filters[:sold] == 'sales'
    scope.where(id: orders.select(:contact_id))
  end

  # 'own' = contactos propios de la cuenta, no traídos por un afiliado.
  def apply_affiliate_filter(scope)
    return scope.where(jabvox_affiliate_id: nil) if @filters[:affiliate_id] == 'own'
    return scope if @filters[:affiliate_id].blank?

    scope.where(jabvox_affiliate_id: Array(@filters[:affiliate_id]))
  end

  def apply_conversation_filters(scope)
    scope = apply_assignee_filter(scope)
    keys = %i[inbox_id team_id status]
    return scope if keys.none? { |k| @filters[k].present? }

    convs = @account.conversations
    convs = convs.where(inbox_id: Array(@filters[:inbox_id])) if @filters[:inbox_id].present?
    convs = convs.where(team_id: @filters[:team_id]) if @filters[:team_id].present?
    convs = convs.where(status: @filters[:status]) if @filters[:status].present?
    scope.where(id: convs.select(:contact_id))
  end

  # Filtrar por responsable cubre AMBAS vías: el asignado propio del contacto y el de su
  # conversación. Si solo mirara el del contacto, no encontraría a los que tienen dueño
  # únicamente por la conversación, que es el caso más común.
  def apply_assignee_filter(scope)
    assignee = @filters[:assignee_id].presence || @filters[:conversation_assignee_id].presence
    return scope if assignee.blank?

    by_conversation = @account.conversations.where(assignee_id: assignee).select(:contact_id)
    scope.where('contacts.assignee_id = :a OR contacts.id IN (:ids)',
                a: assignee, ids: by_conversation)
  end

  # Una gestión vive como mensaje privado (si hubo conversación) o como nota del contacto
  # (si no la hubo): se unen ambas fuentes o se perderían los gestionados solo por nota.
  def apply_management_filters(scope)
    return scope unless @filters[:management_state].present? ||
                        @filters[:date_from].present? || @filters[:date_to].present?

    from = safe_date(@filters[:date_from])
    to = safe_date(@filters[:date_to])
    scope.where(id: management_contact_ids(from, to))
  end

  def management_contact_ids(from, to)
    from_messages = with_state_and_range(@account.messages.where(private: true), 'messages', from, to)
    ids = @account.conversations.where(id: from_messages.select(:conversation_id))
                  .reorder(nil).distinct.pluck(:contact_id).compact
    return ids unless Note.column_names.include?('contact_id')

    ids | with_state_and_range(@account.notes, 'notes', from, to).reorder(nil).distinct.pluck(:contact_id).compact
  end

  # Una gestión se reconoce porque lleva ID de estado de gestión; una nota privada normal
  # solo tiene texto.
  def with_state_and_range(scope, table, from, to)
    id_sql = "(#{table}.content_attributes #>> '{}')::json->>'jabvox_management_state_id'"
    name_sql = "(#{table}.content_attributes #>> '{}')::json->>'jabvox_management_state_name'"
    scope = scope.where("#{id_sql} IS NOT NULL AND #{id_sql} <> ''")
    scope = scope.where("#{name_sql} IN (?)", Array(@filters[:management_state])) if @filters[:management_state].present?
    scope = scope.where("#{table}.created_at >= ?", from.beginning_of_day) if from
    scope = scope.where("#{table}.created_at <= ?", to.end_of_day) if to
    scope
  end

  # Una fecha mal formada no debe filtrar nada ni tumbar la petición.
  def safe_date(value)
    value.present? ? Date.parse(value.to_s) : nil
  rescue ArgumentError, TypeError
    nil
  end

  def like(value)
    ActiveRecord::Base.sanitize_sql_like(value.to_s)
  end

  def order_clause
    col = SORTABLE_COLUMNS[@filters[:sort_column]] || 'contacts.created_at'
    dir = @filters[:sort_direction] == 'asc' ? 'ASC' : 'DESC'
    Arel.sql("#{col} #{dir}")
  end
end
