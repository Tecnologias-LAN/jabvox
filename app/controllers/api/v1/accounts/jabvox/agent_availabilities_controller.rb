# frozen_string_literal: true

# Gestiona el horario laboral por agente que usa Jabvox IA para calcular la
# disponibilidad de citas. Se opera por agente: `show` devuelve las franjas de
# un agente (una por día de la semana) y `update` las reemplaza en bloque.
class Api::V1::Accounts::Jabvox::AgentAvailabilitiesController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_calendar_access
  before_action :ensure_module_permission
  before_action :set_agent, only: %i[show update]

  # Lista los agentes de la cuenta con si tienen o no horario configurado, para
  # poblar el selector de la UI.
  def index
    configured = JabvoxAgentAvailability.where(account_id: Current.account.id)
                                        .group(:user_id).count
    # Entrada especial "company" (horario de empresa, fallback) al inicio.
    company = { id: 'company', name: 'Horario de empresa (por defecto)', email: nil,
                availabilities_count: configured[nil].to_i }
    agents = Current.account.users.order(:name).map do |user|
      { id: user.id, name: user.name, email: user.email,
        availabilities_count: configured[user.id].to_i }
    end
    render json: [company, *agents]
  end

  def show
    render json: {
      agent: @agent ? { id: @agent.id, name: @agent.name } : { id: 'company', name: 'Horario de empresa' },
      availabilities: agent_availabilities.map { |a| serialize(a) }
    }
  end

  # Reemplaza en bloque el horario del agente con las franjas recibidas. Una
  # franja por día (day_of_week 0..6); los días omitidos quedan sin atención.
  def update
    ActiveRecord::Base.transaction do
      agent_availabilities.delete_all
      availabilities_param.each { |attrs| create_availability(attrs) }
    end
    render json: { availabilities: agent_availabilities.reload.map { |a| serialize(a) } }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private

  def create_availability(attrs)
    Current.account.jabvox_agent_availabilities.create!(
      user_id: @agent_user_id,
      day_of_week: attrs[:day_of_week],
      start_minute: attrs[:start_minute],
      end_minute: attrs[:end_minute],
      slot_minutes: attrs[:slot_minutes].presence || 30,
      active: attrs.key?(:active) ? attrs[:active] : true
    )
  end

  def agent_availabilities
    @agent_availabilities ||= Current.account.jabvox_agent_availabilities
                                     .where(user_id: @agent_user_id)
                                     .order(:day_of_week)
  end

  # El id especial "company" gestiona el horario de EMPRESA (user_id NULL), usado
  # como fallback para agentes sin horario propio. Cualquier otro id es un agente.
  def set_agent
    if params[:id] == 'company'
      @agent = nil
      @agent_user_id = nil
      return
    end
    @agent = Current.account.users.find(params[:id])
    @agent_user_id = @agent.id
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Agente no encontrado' }, status: :not_found
  end

  def availabilities_param
    params.permit(availabilities: %i[day_of_week start_minute end_minute slot_minutes active])
          .fetch(:availabilities, [])
          .map(&:to_h)
          .map(&:symbolize_keys)
  end

  def check_calendar_access
    return if Current.account.jabvox_calendar_enabled_jabvox?
    return if Current.account.jabvox_smtp_config.present?

    render json: { error: 'Calendar module not enabled' }, status: :forbidden
  end

  def ensure_module_permission
    jabvox_authorize_write!('jabvox_calendar_manage')
  end

  def serialize(availability)
    {
      id: availability.id,
      day_of_week: availability.day_of_week,
      start_minute: availability.start_minute,
      end_minute: availability.end_minute,
      slot_minutes: availability.slot_minutes,
      active: availability.active
    }
  end
end
