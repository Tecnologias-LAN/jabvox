# frozen_string_literal: true

# jabvox.calendar.delete_event — borra un evento de la cuenta del run.
class Jabvox::Flows::Nodes::Jabvox::CalendarDeleteEventNode < Jabvox::Flows::Nodes::Jabvox::CalendarBase
  type 'jabvox.calendar.delete_event'
  label 'Eliminar Evento'

  def perform
    event = find_event!(param(:eventId))
    title = event.title
    event.destroy!
    { 'deleted' => true, 'eventId' => event.id, 'title' => title }
  end
end
