# frozen_string_literal: true

# Reaper de miembros fantasma en las colas del dialer (cron cada 1 min).
#
# Un agente entra a la cola de Asterisk al conectarse y solo debería salir al
# desconectarse; si cierra el navegador o se le cae la red, el `disconnect` no
# corre y queda como fantasma recibiendo llamadas. Encola una reconciliación por
# cuenta (DialerQueueReconcileAccountJob) en la cola aislada.
#
# O(activas), no O(cuentas): solo reconcilia cuentas con actividad viva de dialer
# — con una llamada abierta (índice parcial idx_dialer_logs_open_by_account) o
# con agentes conectados (SET Redis jabvox_dialer_connected_*). Sin esto, a 1000
# cuentas encolaría 1000 jobs AMI por minuto aunque casi ninguna esté marcando.
class Jabvox::DialerQueueReaperJob < ApplicationJob
  queue_as :jabvox_ami

  # Si la cola aún arrastra trabajo de la corrida anterior, saltamos esta pasada
  # para no apilar minuto a minuto. El debounce por cuenta evita duplicar.
  BACKLOG_CEILING = 500

  def perform
    if queue_backlogged?
      Rails.logger.warn('[DialerQueueReaper] backlog alto en jabvox_ami; salto esta corrida')
      return
    end

    enqueued = 0
    active_account_ids.each do |account_id|
      Jabvox::DialerQueueReconcileAccountJob.perform_later(account_id, source: 'reaper')
      enqueued += 1
    rescue StandardError => e
      Rails.logger.error("[DialerQueueReaper] no se pudo encolar cuenta=#{account_id} #{e.class}: #{e.message}")
    end
    Rails.logger.info("[DialerQueueReaper] reconciliaciones encoladas: #{enqueued}") if enqueued.positive?
  end

  private

  # Cuentas con dialer VIVO: llamada abierta (SQL, índice parcial) ∪ agentes
  # conectados (Redis). Interseca con las que tienen VoIP configurado.
  def active_account_ids
    ids = accounts_with_open_calls | accounts_with_connected_agents
    return ids if ids.empty?

    Account.joins(:jabvox_voip_config).where(id: ids).pluck(:id)
  end

  def accounts_with_open_calls
    JabvoxDialerCallLog.where(status_jabvox: %w[initiated calling]).distinct.pluck(:account_id)
  rescue StandardError
    []
  end

  # SCAN de los SET jabvox_dialer_connected_<id> no vacíos.
  def accounts_with_connected_agents
    ids = []
    Redis::Alfred.scan_each(match: 'jabvox_dialer_connected_*') do |key|
      account_id = key.split('_').last.to_i
      ids << account_id if account_id.positive?
    end
    ids.uniq
  rescue StandardError
    []
  end

  def queue_backlogged?
    Sidekiq::Queue.new('jabvox_ami').size > BACKLOG_CEILING
  rescue StandardError
    false
  end
end
