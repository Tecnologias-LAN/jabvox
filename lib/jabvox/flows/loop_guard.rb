# frozen_string_literal: true

# Guardia anti-bucle del motor de Flows.
#
# Un flujo cuyo TRIGGER es un evento y cuya ACCIÓN provoca ese mismo evento se
# retroalimenta en bucle (incidente real: 55.000 ejecuciones en 1 hora + ~200
# WhatsApp enviados). Esta guardia cuenta, en una ventana corta, cuántas veces se
# dispara un mismo flujo; si supera el umbral, lo AUTO-PAUSA (status: paused) y deja
# constancia, cortando la hemorragia en segundos.
#
# Diseño:
# - Contador por flow en Redis (INCR + EXPIRE) — O(1), no golpea Postgres en el worker
#   más caliente (el despacho de eventos). Ventana fija por TTL.
# - FAIL-OPEN: si Redis no responde, NO se bloquea el disparo (igual que
#   Jabvox::RedisLock) — preferible dejar correr que frenar tráfico legítimo.
# - Umbral/ventana configurables por ENV para ajuste operativo sin re-deploy.
# - Solo se usa en el disparo por EVENTO (EventDispatchService), que es de donde
#   viene el bucle; manual/schedule/webhook no pasan por aquí.
module Jabvox::Flows::LoopGuard
  # > THRESHOLD runs en WINDOW segundos por flow = anómalo. El incidente real
  # rondó 15 runs/s; 30/60s lo corta en ~2s y deja amplio margen a tráfico humano.
  THRESHOLD = ENV.fetch('JABVOX_FLOWS_LOOP_THRESHOLD', 30).to_i
  WINDOW    = ENV.fetch('JABVOX_FLOWS_LOOP_WINDOW', 60).to_i

  module_function

  # Devuelve true si el flujo superó el umbral en la ventana y debe SALTARSE su
  # disparo (y además queda auto-pausado). Fail-open ante cualquier fallo.
  def tripped?(flow)
    count = record_and_count(flow.id)
    return false if count <= THRESHOLD

    trip!(flow, count)
    true
  rescue StandardError => e
    Rails.logger.error("[Flows::LoopGuard] flow=#{flow&.id} #{e.class}: #{e.message}")
    false
  end

  # Incrementa el contador del flow y fija el TTL al crear la ventana. Devuelve el
  # conteo actual. El TTL se (re)asegura si la llave quedó sin expiración (carrera
  # benigna INCR/EXPIRE), para que nunca sea permanente.
  def record_and_count(flow_id)
    key = format(Redis::RedisKeys::JABVOX_FLOW_RUN_RATE, flow_id: flow_id)
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, WINDOW) if count == 1 || Redis::Alfred.ttl(key).to_i.negative?
    count
  end

  # Auto-pausa el flujo (idempotente: solo si seguía activo), deja un run "fallido"
  # con el motivo visible en el historial, y avisa una sola vez por ventana.
  def trip!(flow, count)
    # update_all a propósito: pausa atómica e idempotente (si dos procesos cruzan el
    # umbral a la vez, solo uno "gana" y avisa); no hay validaciones que ejecutar.
    paused = JabvoxFlow.where(id: flow.id, status: :active)
                       .update_all(status: JabvoxFlow.statuses[:paused], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    return if paused.zero? # otro proceso ya lo pausó

    notify_once(flow, count)
    record_sentinel_run(flow, count)
  end

  def notify_once(flow, count)
    key = format(Redis::RedisKeys::JABVOX_FLOW_LOOP_NOTIFIED, flow_id: flow.id)
    first = Redis::Alfred.set(key, '1', nx: true, ex: WINDOW)
    return unless first

    message = "Flow ##{flow.id} auto-pausado por protección anti-bucle: #{count} ejecuciones en #{WINDOW}s (umbral #{THRESHOLD})."
    Rails.logger.warn("[Flows::LoopGuard] #{message}")
    JabvoxExceptionTracker.new(StandardError.new(message), account: flow.account).capture_exception
  rescue StandardError => e
    Rails.logger.error("[Flows::LoopGuard] notify flow=#{flow.id} #{e.class}: #{e.message}")
  end

  # Run-centinela: una ejecución "failed" con el motivo, para que el usuario vea en el
  # historial del flujo POR QUÉ se auto-pausó, sin necesidad de migración.
  def record_sentinel_run(flow, count)
    version_id = flow.current_version_id
    return if version_id.blank?

    JabvoxFlowRun.create!(
      account_id: flow.account_id,
      flow_id: flow.id,
      version_id: version_id,
      status: :failed,
      trigger: { 'type' => 'loop_guard' },
      error: "Auto-pausado por protección anti-bucle: #{count} ejecuciones en #{WINDOW}s " \
             "(umbral #{THRESHOLD}). Revisa que la acción del flujo no vuelva a disparar su " \
             'propio evento. Reactívalo cuando esté corregido.',
      started_at: Time.current,
      finished_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[Flows::LoopGuard] sentinel flow=#{flow.id} #{e.class}: #{e.message}")
  end
end
