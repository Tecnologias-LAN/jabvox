# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::CalendarExternalPeopleController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_calendar_access
  before_action :ensure_module_permission
  before_action :set_person, only: %i[show update destroy]

  def index
    people = Current.account.jabvox_calendar_external_people.ordered
    render json: people.map { |p| serialize(p) }
  end

  def show
    render json: serialize(@person)
  end

  def create
    person = Current.account.jabvox_calendar_external_people.new(person_params)
    person.save!
    render json: serialize(person), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @person.update!(person_params)
    render json: serialize(@person)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @person.destroy!
    head :ok
  end

  private

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

  def set_person
    @person = Current.account.jabvox_calendar_external_people.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def person_params
    params.permit(:name, :email, :phone_number, :notes, :color)
  end

  def serialize(person)
    {
      id: person.id,
      name: person.name,
      email: person.email,
      phone_number: person.phone_number,
      notes: person.notes,
      color: person.color,
      events_count: person.jabvox_calendar_event_participants.count,
      created_at: person.created_at
    }
  end
end
