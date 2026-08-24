# frozen_string_literal: true

# Auditoría de acciones de Hermes de la cuenta (solo lectura). Solo el admin del Chat IA la
# ve. Estrictamente scopeado a Current.account (no hay forma de ver logs de otra cuenta).
#
#   GET .../jabvox/hermes_action_logs?tool=&status=&page= → logs paginados
class Api::V1::Accounts::Jabvox::HermesActionLogsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  jabvox_feature 'jabvox_ai_chat'
  before_action -> { jabvox_authorize!('jabvox_ai_chat_manage') }

  PER_PAGE = 50

  def index
    logs = filtered_logs.order(created_at: :desc).page(params[:page] || 1).per(PER_PAGE)
    render json: {
      logs: logs.map { |l| serialize(l) },
      meta: { total: logs.total_count, current_page: logs.current_page, total_pages: logs.total_pages }
    }
  end

  private

  def filtered_logs
    logs = JabvoxHermesActionLog.where(account_id: Current.account.id)
    logs = logs.where(tool_jabvox: params[:tool]) if params[:tool].present?
    logs = logs.where(status_jabvox: params[:status]) if params[:status].present?
    logs
  end

  def serialize(log)
    {
      id: log.id, created_at: log.created_at, user_id: log.user_id,
      hermes_identity: log.hermes_identity_jabvox, tool: log.tool_jabvox,
      permission: log.permission_jabvox, status: log.status_jabvox,
      params: log.params_jabvox, error: log.error_jabvox, duration_ms: log.duration_ms_jabvox
    }
  end
end
