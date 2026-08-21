# frozen_string_literal: true

# P3 — Reconciliación por EVENTO de una sola cuenta, disparada tras un disconnect.
#
# El reaper periódico (DialerQueueReaperJob) corre cada minuto; eso deja hasta ~60s
# en que un agente fantasma sigue en la cola y le entran llamadas. Este job cierra
# esa ventana: al desconectarse un agente, encolamos una reconciliación INMEDIATA de
# su cuenta, con debounce en Redis para que una ráfaga de desconexiones (varios
# agentes a la vez) no dispare N pasadas AMI concurrentes contra el mismo PBX.
class Jabvox::DialerQueueReconcileAccountJob < ApplicationJob
  queue_as :jabvox_ami

  # Ventana de debounce: dentro de estos segundos, una cuenta se reconcilia una sola
  # vez aunque se encolen varias veces (varios disconnects seguidos).
  DEBOUNCE_TTL = 5

  # Cuánto saltar una cuenta cuyo PBX no respondió, para no gastar el connect-timeout
  # contra servidores apagados. Al expirar se reintenta sola.
  UNREACHABLE_TTL = 90

  # source: 'reaper' (fan-out del cron) | 'event' (disconnect); solo para el log.
  def perform(account_id, source: 'event')
    account = Account.find_by(id: account_id)
    return if account.nil?
    return if pbx_unreachable_cached?(account_id)
    return unless acquire_debounce(account_id)

    result = Jabvox::DialerQueueReconcilerService.reconcile_account(account)
    mark_unreachable(account_id) if result[:reachable] == false
    Rails.logger.info("[DialerQueueReconcileAccount] cuenta=#{account_id} src=#{source} removidos=#{result[:removed]}")
  rescue StandardError => e
    Rails.logger.error("[DialerQueueReconcileAccount] cuenta=#{account_id} #{e.class}: #{e.message}")
  end

  private

  def unreachable_key(account_id)
    "jabvox_dialer_pbx_unreachable_#{account_id}"
  end

  def pbx_unreachable_cached?(account_id)
    Redis::Alfred.get(unreachable_key(account_id)).present?
  rescue StandardError
    false
  end

  def mark_unreachable(account_id)
    Redis::Alfred.set(unreachable_key(account_id), Time.current.to_i, ex: UNREACHABLE_TTL)
  rescue StandardError => e
    Rails.logger.warn("[DialerQueueReconcileAccount] no se pudo cachear PBX caído cuenta=#{account_id} | #{e.message}")
  end

  # true solo para el primer encolado dentro de la ventana; los demás se descartan.
  # SET NX EX es atómico: dos jobs concurrentes de la misma cuenta no reconcilian dos veces.
  def acquire_debounce(account_id)
    Redis::Alfred.set("jabvox_dialer_reconcile_debounce_#{account_id}",
                      Time.current.to_i, nx: true, ex: DEBOUNCE_TTL)
  rescue StandardError
    # Si Redis no responde, no bloqueamos la reconciliación (falla abierto).
    true
  end
end
