# frozen_string_literal: true

# Historial y diagnóstico de llamadas del softphone del usuario actual. Gateado por el
# módulo jabvox_softphone; cada usuario solo ve/gestiona SUS propias llamadas.
#
#   GET    .../call_logs             → historial (recientes primero, con eventos)
#   POST   .../call_logs             → registra el inicio de una llamada
#   PATCH  .../call_logs/:id          → actualiza (contestada/cerrada/codec/fallo)
#   POST   .../call_logs/:id/event    → registra un evento de la llamada (dtmf, hold, error…)
#
# ROBUSTEZ: cada acción está aislada; un error en una llamada no afecta a otras ni tumba el
# proceso. El registro de eventos nunca hace fallar la operación principal.
class Api::V1::Accounts::Jabvox::Softphone::CallLogsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_softphone'

  before_action :fetch_log, only: [:update, :event]

  def index
    @logs = Current.account.jabvox_softphone_call_logs
                   .for_user(Current.user.id).recent_first.limit(100)
    render json: @logs.map { |log| serialize(log) }
  end

  def create
    log = Current.account.jabvox_softphone_call_logs.new(create_params)
    log.user = Current.user
    log.started_at ||= Time.current
    log.save!
    logger_for(log).event('invite', detail: log.phone_number)
    render json: serialize(log), status: :created
  end

  def update
    if params[:finish]
      extra = update_params.to_h.compact
      @log.update!(extra) if extra.present?
      @log.finish!(status: (params[:status].presence || 'ended').to_sym)
      logger_for(@log).event('hangup', detail: @log.status)
    else
      @log.update!(update_params)
      logger_for(@log).event('answer') if params[:status] == 'answered'
    end
    render json: serialize(@log)
  end

  # Registra un evento suelto de la llamada (dtmf, hold, transfer, error, codec…).
  def event
    logger_for(@log).event(params[:event_type].to_s, detail: params[:detail])
    head :ok
  end

  private

  def fetch_log
    @log = Current.account.jabvox_softphone_call_logs
                  .for_user(Current.user.id).find(params[:id])
  end

  def logger_for(log)
    Jabvox::Softphone::CallLogger.new(log)
  end

  def create_params
    params.permit(:phone_number, :extension, :contact_name, :direction, :call_uuid,
                  :started_at, :sip_context)
  end

  def update_params
    params.permit(:status, :contact_name, :answered_at, :ended_at, :duration_seconds,
                  :codec, :failure_reason, :failure_code, :remote_ip, :ended_by)
  end

  def serialize(log)
    {
      id: log.id,
      phone_number: log.phone_number,
      contact_name: log.contact_name,
      extension: log.extension,
      direction: log.direction,
      status: log.status,
      codec: log.codec,
      failure_reason: log.failure_reason,
      ended_by: log.ended_by,
      duration_seconds: log.duration_seconds,
      started_at: log.started_at,
      created_at: log.created_at
    }
  end
end
