# Keeps a task's due date(s) in sync with the real Jabvox Calendar: each due date becomes a
# calendar event (event_type: task) owned by the assignee (or the task creator). Re-syncing
# replaces the task's previous events, so editing dates never leaves orphans or duplicates.
#
#   Jabvox::TaskCalendarSyncService.new(task).sync!
class Jabvox::TaskCalendarSyncService
  EVENT_MINUTES = 30

  def initialize(task)
    @task = task
    @account = task.account
  end

  def sync!
    events = @account.jabvox_calendar_events.where(jabvox_task_id: @task.id)
    if @task.deleted_at_jabvox.present?
      events.destroy_all
      return
    end
    return if owner.nil?

    # Replace this task's events with a fresh set built from its current dates.
    events.destroy_all
    due_dates.each { |date| create_event(date) }
  end

  private

  # The task owner for the calendar: its assignee, else whoever created it.
  def owner
    @owner ||= @task.assignee || @task.created_by
  end

  # All dates for the task: the multi-date jsonb if present, otherwise the single due_at.
  def due_dates
    list = Array(@task.due_dates_jabvox).filter_map { |d| parse_time(d) }
    list = [@task.due_at_jabvox].compact if list.empty?
    list
  end

  def parse_time(value)
    value.is_a?(Time) ? value : Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def create_event(date)
    @account.jabvox_calendar_events.create!(
      user: owner,
      jabvox_task_id: @task.id,
      # El contacto cuelga de la tarea desde que se unificó Leads en Contactos: la
      # asociación `jabvox_lead` ya no existe en JabvoxTask, así que leerla dejaba el
      # evento de calendario sin contacto.
      contact_id: @task.contact_id,
      title: @task.title_jabvox,
      description: @task.description_jabvox,
      event_type: :task,
      status: @task.status_jabvox == 'done' ? :done : :pending,
      start_at: date,
      end_at: date + EVENT_MINUTES.minutes,
      all_day: false
    )
  end
end
