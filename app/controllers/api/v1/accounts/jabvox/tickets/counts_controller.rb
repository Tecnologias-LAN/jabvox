# Conteos para el badge del menú, respetando el scope de permisos del usuario:
#   today            → solicitudes abiertas creadas HOY (badge verde)
#   overdue_previous → solicitudes abiertas vencidas de días anteriores (badge rojo)
# Sin caché: es un indicador en vivo.
class Api::V1::Accounts::Jabvox::Tickets::CountsController <
      Api::V1::Accounts::Jabvox::Tickets::BaseController
  include Api::V1::Accounts::Jabvox::Tickets::TicketFilters

  def show
    scope = policy_scope(JabvoxTicket).open_tickets
    render json: {
      today: today_count(scope),
      overdue_previous: overdue_previous_count(scope),
      total_pending: scope.count
    }
  end

  private

  # Abiertas creadas dentro del día actual (zona de la cuenta gestora).
  def today_count(scope)
    scope.where(created_at: day_range).count
  end

  # Abiertas vencidas (pasaron su SLA) creadas antes de hoy.
  def overdue_previous_count(scope)
    scope.where('due_at_jabvox IS NOT NULL AND due_at_jabvox < ?', Time.current)
         .where('created_at < ?', day_range.begin)
         .count
  end

  def day_range
    zone = tickets_time_zone
    now = Time.current.in_time_zone(zone)
    now.all_day
  end
end
