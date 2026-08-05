# Filtros y paginación del listado de tickets. Extraído del controller para
# mantenerlo bajo el límite de longitud.
module Api::V1::Accounts::Jabvox::Tickets::TicketFilters
  extend ActiveSupport::Concern

  PER_PAGE_OPTIONS = [10, 25, 50, 100].freeze
  DEFAULT_PER_PAGE = 25

  def apply_filters(scope)
    scope = filter_by_search(scope)
    scope = filter_by_category_type(scope)
    scope = filter_by_status(scope)
    scope = filter_by_priority(scope)
    scope = filter_by_category(scope)
    scope = filter_by_assignee(scope)
    scope = filter_by_unassigned(scope)
    scope = filter_by_due_today(scope)
    filter_by_overdue(scope)
  end

  private

  # Full-text sobre la columna tsvector generada (índice GIN, insensible a acentos),
  # en vez de ILIKE '%..%'.
  def filter_by_search(scope)
    term = params[:q].to_s.strip
    return scope if term.blank?

    scope.merge(JabvoxTicket.accent_insensitive_search(term))
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

    today = Time.now.in_time_zone(tickets_time_zone).to_date
    range = today.beginning_of_day.in_time_zone(tickets_time_zone)..today.end_of_day.in_time_zone(tickets_time_zone)
    scope.where(due_at_jabvox: range)
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
