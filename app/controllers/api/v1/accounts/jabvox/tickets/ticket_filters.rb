# Filtros y paginación del listado de tickets. Extraído del controller para
# mantenerlo bajo el límite de longitud.
module Api::V1::Accounts::Jabvox::Tickets::TicketFilters
  extend ActiveSupport::Concern

  PER_PAGE_OPTIONS = [10, 25, 50, 100].freeze
  DEFAULT_PER_PAGE = 25
  # Columnas por las que se puede ordenar (lista blanca → evita inyección/SQL arbitrario).
  SORTABLE_COLUMNS = %w[created_at due_at_jabvox priority_jabvox status_jabvox].freeze
  DEFAULT_SORT = 'created_at'.freeze

  def apply_filters(scope)
    scope = filter_by_search(scope)
    scope = filter_by_display_id(scope)
    scope = filter_by_category_type(scope)
    scope = filter_by_status(scope)
    scope = filter_by_priority(scope)
    scope = filter_by_category(scope)
    scope = filter_by_assignee(scope)
    scope = filter_by_unassigned(scope)
    scope = filter_by_due_today(scope)
    scope = filter_by_date_range(scope)
    filter_by_overdue(scope)
  end

  # Ordenamiento seguro: solo columnas de la lista blanca; por defecto created_at desc.
  def apply_sort(scope)
    column = SORTABLE_COLUMNS.include?(params[:sort_by]) ? params[:sort_by] : DEFAULT_SORT
    direction = params[:sort_dir].to_s.downcase == 'asc' ? :asc : :desc
    scope.order(column => direction)
  end

  private

  # Full-text sobre la columna tsvector generada (índice GIN, insensible a acentos).
  # Si el término es puramente numérico (con o sin #), busca por número de solicitud
  # (display_id) — así escribir "42" encuentra la solicitud #42.
  def filter_by_search(scope)
    term = params[:q].to_s.strip
    return scope if term.blank?

    return scope.where(display_id_jabvox: term.delete('#').to_i) if term.match?(/\A#?\d+\z/)

    scope.merge(JabvoxTicket.accent_insensitive_search(term))
  end

  # Filtro dedicado por número de solicitud (display_id), indexado.
  def filter_by_display_id(scope)
    return scope if params[:display_id].blank?

    scope.where(display_id_jabvox: params[:display_id].to_s.delete('#').to_i)
  end

  def filter_by_category_type(scope)
    return scope if params[:category_type].blank?

    scope.where(category_type_jabvox: params[:category_type])
  end

  def filter_by_status(scope)
    return scope if params[:status].blank?
    # Valor especial 'open': cualquiera de los estados abiertos (para "mis abiertos").
    return scope.open_tickets if params[:status] == 'open'

    scope.where(status_jabvox: params[:status])
  end

  def filter_by_priority(scope)
    return scope if params[:priority].blank?

    scope.where(priority_jabvox: params[:priority])
  end

  def filter_by_category(scope)
    return scope if params[:ticket_category_id].blank?

    scope.where(ticket_category_id: params[:ticket_category_id])
  end

  def filter_by_overdue(scope)
    ActiveModel::Type::Boolean.new.cast(params[:overdue]) ? scope.overdue : scope
  end

  # Vista "mis asignados": tickets de un agente concreto.
  def filter_by_assignee(scope)
    return scope if params[:assignee_id].blank?

    scope.where(assignee_id: params[:assignee_id])
  end

  # Vista "sin asignar": assignee_id IS NULL.
  def filter_by_unassigned(scope)
    return scope unless ActiveModel::Type::Boolean.new.cast(params[:unassigned])

    scope.where(assignee_id: nil)
  end

  # Vista "por vencer hoy": due_at dentro del día actual en la zona de la cuenta.
  def filter_by_due_today(scope)
    return scope unless ActiveModel::Type::Boolean.new.cast(params[:due_today])

    now = Time.current.in_time_zone(tickets_time_zone)
    scope.where(due_at_jabvox: now.all_day)
  end

  # Rango de fechas de creación (date_from / date_to), inclusive, en la zona de la
  # cuenta. Cada extremo es opcional.
  def filter_by_date_range(scope)
    zone = tickets_time_zone
    from = parse_date(params[:date_from])
    to = parse_date(params[:date_to])
    scope = scope.where('created_at >= ?', from.beginning_of_day.in_time_zone(zone)) if from
    scope = scope.where('created_at <= ?', to.end_of_day.in_time_zone(zone)) if to
    scope
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  # Zona horaria para los filtros de fecha: la del horario laboral del helpdesk, con
  # fallback al reporting_timezone de la cuenta y por último UTC.
  def tickets_time_zone
    config = JabvoxTicketHelpdeskConfig.current
    zone_name = config&.business_hours_jabvox.to_h['time_zone']
    zone_name = Current.account.reporting_timezone if zone_name.blank?
    ActiveSupport::TimeZone[zone_name.to_s].presence || ActiveSupport::TimeZone['UTC']
  end
end
