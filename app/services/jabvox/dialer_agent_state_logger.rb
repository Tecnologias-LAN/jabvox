# frozen_string_literal: true

# Registra las transiciones de estado del agente del dialer para que el reporte
# de agentes (tiempos por estado / estado actual) tenga datos reales.
#
# Antes, jabvox_dialer_state_logs y account_users.jabvox_dialer_state solo se
# escribían desde ReportsController#set_dialer_state, que ningún flujo del dialer
# invocaba: el estado vivo solo existía en Redis y el reporte salía en cero.
#
# Este logger es la única fuente de escritura y se llama desde el ciclo de vida
# real del agente: conectar (waiting), pausa/despausa (paused/waiting), en
# llamada (in_call) y desconectar (inactive). Idempotente: si el estado no
# cambió, no abre un registro nuevo.
class Jabvox::DialerAgentStateLogger
  STATES = %w[inactive waiting paused in_call in_wrapup].freeze

  def self.record(account_id:, user_id:, state:)
    new(account_id, user_id, state).record
  end

  def initialize(account_id, user_id, state)
    @account_id = account_id
    @user_id    = user_id
    @state      = STATES.include?(state.to_s) ? state.to_s : 'inactive'
  end

  def record
    now = Time.current
    ApplicationRecord.transaction do
      open = JabvoxDialerStateLog
             .where(account_id: @account_id, user_id: @user_id, ended_at: nil)
             .order(started_at: :desc).lock.to_a
      # Sin cambio de estado: no abrir un registro nuevo (evita fragmentar los
      # tiempos del reporte y escrituras redundantes en cada heartbeat).
      next if open.size == 1 && open.first.dialer_state == @state

      # update_all a propósito: cierre/registro de estado en lote sin callbacks.
      # rubocop:disable Rails/SkipsModelValidations
      JabvoxDialerStateLog.where(id: open.map(&:id)).update_all(ended_at: now) if open.any?
      JabvoxDialerStateLog.create!(account_id: @account_id, user_id: @user_id,
                                   dialer_state: @state, started_at: now)
      AccountUser.where(account_id: @account_id, user_id: @user_id)
                 .update_all(jabvox_dialer_state: @state, jabvox_dialer_state_changed_at: now)
      # rubocop:enable Rails/SkipsModelValidations
    end
  rescue StandardError => e
    # El registro de estado NUNCA debe tumbar el flujo de marcación.
    Rails.logger.error "❌ [Dialer] DialerAgentStateLogger failed | user=#{@user_id} #{e.class}: #{e.message}"
  end
end
