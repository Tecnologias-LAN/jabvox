# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::CalendarEventsController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_calendar_access
  before_action :ensure_module_permission
  before_action :set_event, only: %i[show update destroy]
  before_action :ensure_can_manage!, only: %i[update destroy]

  def index
    render json: index_scope.ordered.map { |e| serialize(e) }
  end

  def show
    render json: serialize(@event)
  end

  # Accepts either a single slot (start_at/end_at) or multiple `slots`, and an
  # optional `participants` array. Creates one event per slot.
  def create
    events = Jabvox::CalendarEventBuilder.new(
      account: Current.account,
      user: Current.user,
      attributes: event_attributes,
      slots: slots_param,
      participants: participants_param
    ).perform!

    notify_participants(events)
    render json: events.map { |e| serialize(e) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @event.update!(event_attributes)
    sync_participants(@event) if params.key?(:participants)
    render json: serialize(@event)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    if params[:scope] == 'group' && @event.recurrence_group_id.present?
      destroy_series
    else
      @event.destroy!
    end
    head :ok
  end

  private

  # Rango pedido, con el mes actual por defecto. Se precargan sede, contacto y
  # participantes: el serializador los lee de cada fila y sin esto son tres consultas por
  # evento.
  def index_scope
    from, to = index_range
    events = Current.account.jabvox_calendar_events
                    .includes(:branch, :contact, jabvox_calendar_event_participants: %i[user])
                    .for_range(from, to)
    # scope: 'mine' shows only events the current user owns or participates in;
    # 'team' (default) shows the whole account so you can see your team's calendar.
    events = events.visible_to_user(Current.user.id) if params[:scope] == 'mine'
    events = events.for_user(params[:user_id]) if params[:user_id].present?
    events
  end

  def index_range
    from = params[:from].present? ? Time.zone.parse(params[:from]) : Time.zone.now.beginning_of_month
    to = params[:to].present? ? Time.zone.parse(params[:to]) : Time.zone.now.end_of_month
    [from, to]
  end

  def check_calendar_access
    return if Current.account.jabvox_calendar_enabled_jabvox?
    return if Current.account.jabvox_smtp_config.present?

    render json: { error: 'Calendar module not enabled' }, status: :forbidden
  end

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_calendar_manage')
  end

  def set_event
    @event = Current.account.jabvox_calendar_events.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  # Borrar una serie recurrente pasa por la política EVENTO POR EVENTO. El gate de la
  # acción solo valida el evento que se pidió, y aquí se borran N: estar invitado a una
  # cita de la serie permitía borrar las otras cuatro, que ni siquiera se podían ver.
  # Lo que no se puede borrar se deja en pie en vez de fallar entera.
  def destroy_series
    Current.account.jabvox_calendar_events
           .where(recurrence_group_id: @event.recurrence_group_id)
           .includes(:jabvox_calendar_event_participants)
           # rubocop:disable Rails/FindEach -- find_each descarta el includes y la
           # política leería los participantes de cada fila; una serie son unas pocas.
           .each { |event| event.destroy! if policy(event).manage? }
    # rubocop:enable Rails/FindEach
  end

  # Editar o borrar la cita de otro no se impide ocultando el botón: se rechaza aquí.
  # Un agente solo toca lo suyo (lo que organiza o donde participa); el administrador,
  # cualquier cosa de su cuenta.
  def ensure_can_manage!
    return if policy(@event).manage?

    render json: { error: 'No tienes permiso para esta acción' }, status: :forbidden
  end

  def event_attributes
    params.permit(
      :title, :description, :note, :all_day,
      :event_type, :status, :color, :contact_id, :branch_id,
      :remind_before_day, :remind_before_hour
    )
  end

  # One slot from top-level start_at/end_at, or the `slots` array if present.
  def slots_param
    if params[:slots].present?
      params[:slots].map { |s| s.permit(:start_at, :end_at, :all_day).to_h }
    else
      [{ start_at: params[:start_at], end_at: params[:end_at], all_day: params[:all_day] }]
    end
  end

  # Los invitados que no son de la cuenta se descartan antes de guardarlos: sin esto se
  # podía colar un usuario de otra cuenta y el serializador devolvía su nombre y su email.
  def participants_param
    rows = params[:participants].presence || []
    rows = rows.map { |p| p.permit(:user_id, :external_person_id, :note).to_h }
    Jabvox::CalendarParticipantsFilter.new(Current.account).call(rows)
  end

  # Replace the participant set on update.
  def sync_participants(event)
    event.jabvox_calendar_event_participants.destroy_all
    participants_param.each do |attrs|
      event.jabvox_calendar_event_participants.create!(
        user_id: attrs['user_id'] || attrs[:user_id],
        jabvox_calendar_external_person_id: attrs['external_person_id'] || attrs[:external_person_id],
        note: (attrs['note'] || attrs[:note]).presence || event.note
      )
    end
  end

  # Email the auto-note to external participants right away (team members see it in-app).
  def notify_participants(events)
    Jabvox::CalendarParticipantNotifier.new(events: events, account: Current.account).perform
  rescue StandardError => e
    Rails.logger.error("[Calendar] participant notify failed: #{e.message}")
  end

  # El detalle completo solo para quien organiza, participa o administra. Al resto se le
  # manda la versión de ocupación: cuándo está ocupado y poco más. Filtrar en el
  # serializador y no en la vista es lo que impide leerlo desde las herramientas del
  # navegador.
  def serialize(event)
    return busy_view(event) unless policy(event).full_detail?

    busy_view(event).merge(
      title: event.title,
      description: event.description,
      note: event.note,
      contact_id: event.contact_id,
      contact_name: event.contact&.name,
      contact_email: event.contact&.email,
      remind_before_day: event.remind_before_day,
      remind_before_hour: event.remind_before_hour,
      participants: event.jabvox_calendar_event_participants.map { |p| serialize_participant(p) },
      can_manage: true
    )
  end

  # Lo que ve un compañero: que la franja está ocupada. Sin contacto, sin notas, sin
  # invitados. El título se sustituye por una etiqueta genérica porque a menudo lleva el
  # nombre del cliente.
  def busy_view(event)
    {
      id: event.id,
      title: I18n.t('jabvox.calendar.busy', default: 'Ocupado'),
      start_at: event.start_at,
      end_at: event.end_at,
      all_day: event.all_day,
      event_type: event.event_type,
      status: event.status,
      color: event.color,
      # La sede va en la vista de ocupación, no en el detalle: saber DÓNDE está ocupado un
      # compañero es lo que permite cuadrar agendas, y no revela nada del cliente.
      branch_id: event.branch_id,
      branch_name: event.branch&.name_jabvox,
      recurrence_group_id: event.recurrence_group_id,
      user_id: event.user_id,
      created_at: event.created_at,
      participants: [],
      can_manage: false
    }
  end

  def policy(event)
    Jabvox::CalendarEventPolicy.new(event, Current.account_user)
  end

  def serialize_participant(participant)
    {
      id: participant.id,
      user_id: participant.user_id,
      external_person_id: participant.jabvox_calendar_external_person_id,
      name: participant.display_name,
      email: participant.email,
      note: participant.note,
      response_status: participant.response_status,
      kind: participant.team_member? ? 'team' : 'external'
    }
  end
end
