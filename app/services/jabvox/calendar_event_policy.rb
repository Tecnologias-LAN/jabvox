# frozen_string_literal: true

# Quién puede ver el detalle de una cita y quién puede tocarla.
#
# El calendario es de equipo: ver la ocupación de un compañero es normal y necesario para
# cuadrar horarios. Ver CON QUIÉN se reúne y POR QUÉ, no. Antes el listado devolvía
# `description`, `note`, el nombre y el email del contacto de TODAS las citas de la cuenta
# a cualquier agente, así que la agenda de un comercial revelaba su cartera entera.
#
# Dos niveles:
#   - completo: es tuya (la creaste o participas) o eres administrador
#   - ocupado:  solo título genérico, franja horaria y estado; sin contacto ni notas
#
# Mutar exige el nivel completo: el backend rechaza, no basta con esconder el botón.
class Jabvox::CalendarEventPolicy
  def initialize(event, account_user)
    @event = event
    @account_user = account_user
  end

  # Ve el detalle quien organiza la cita, quien está invitado, o un administrador.
  def full_detail?
    return false if @account_user.nil?
    return true if @account_user.administrator?
    return true if @event.user_id == @account_user.user_id

    participant?
  end

  # Editar y borrar exigen lo mismo que ver el detalle: si no es tuya, no se toca.
  alias manage? full_detail?

  private

  def participant?
    @event.jabvox_calendar_event_participants.any? { |p| p.user_id == @account_user.user_id }
  end
end
