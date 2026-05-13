# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::CalendarEventsController < Api::V1::Accounts::BaseController
  before_action :check_calendar_access
  before_action :set_event, only: %i[show update destroy]

  def index
    from = params[:from].present? ? Time.zone.parse(params[:from]) : Time.zone.now.beginning_of_month
    to   = params[:to].present? ? Time.zone.parse(params[:to]) : Time.zone.now.end_of_month

    events = Current.account.jabvox_calendar_events.for_range(from, to).ordered
    render json: events.map { |e| serialize(e) }
  end

  def show
    render json: serialize(@event)
  end

  def create
    event = Current.account.jabvox_calendar_events.new(event_params)
    event.user = Current.user
    event.save!
    render json: serialize(event), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @event.update!(event_params)
    render json: serialize(@event)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @event.destroy!
    head :ok
  end

  private

  def check_calendar_access
    return if Current.account.jabvox_calendar_enabled_jabvox?
    return if Current.account.jabvox_smtp_config.present?

    render json: { error: 'Calendar module not enabled' }, status: :forbidden
  end

  def set_event
    @event = Current.account.jabvox_calendar_events.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def event_params
    params.permit(
      :title, :description, :start_at, :end_at, :all_day,
      :event_type, :status, :color, :contact_id,
      :remind_before_day, :remind_before_hour
    )
  end

  def serialize(event)
    {
      id: event.id,
      title: event.title,
      description: event.description,
      start_at: event.start_at,
      end_at: event.end_at,
      all_day: event.all_day,
      event_type: event.event_type,
      status: event.status,
      color: event.color,
      contact_id: event.contact_id,
      contact_name: event.contact&.name,
      contact_email: event.contact&.email,
      remind_before_day: event.remind_before_day,
      remind_before_hour: event.remind_before_hour,
      user_id: event.user_id,
      created_at: event.created_at
    }
  end
end
