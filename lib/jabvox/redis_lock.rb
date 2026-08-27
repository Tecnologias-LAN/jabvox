# frozen_string_literal: true

# Lock distribuido en Redis con HEARTBEAT: mientras el bloque corre, un hilo
# renueva el TTL, de modo que el lock nunca expira a mitad de un job vivo (evita
# el doble-procesamiento cuando la duración real supera un TTL fijo) y se libera
# solo si el proceso muere de verdad. Independiente del p99 del job.
#
# Uso:
#   Jabvox::RedisLock.with_lock("jabvox:lead_import:sync:#{id}") do |lock|
#     ...trabajo largo...
#     return unless lock.held?   # fencing: aborta si perdimos el lock (proceso
#                                # congelado más allá del TTL cuyo lock tomó otro)
#   end
# Devuelve el valor del bloque, o :locked si otro proceso ya lo tenía.
module Jabvox::RedisLock
  DEFAULT_TTL = 60          # s; TTL base, renovado por el heartbeat
  HEARTBEAT_DIVISOR = 3     # renueva cada TTL/3 (2 renovaciones antes de expirar)
  NOT_ACQUIRED = :locked

  # Fencing handle que se pasa al bloque: permite comprobar, justo antes de una
  # escritura crítica, que SEGUIMOS siendo dueños del lock. Un proceso que se
  # congeló más allá del TTL (y cuyo lock tomó otro) verá held? == false y aborta,
  # en vez de escribir doble.
  Handle = Struct.new(:key, :token) do
    def held?
      Jabvox::RedisLock.owner?(key, token)
    end
  end

  module_function

  # Ejecuta el bloque con el lock tomado. Si no se pudo tomar (ya lo tiene otro),
  # devuelve NOT_ACQUIRED sin ejecutar. token único => solo el dueño libera/renueva.
  # El bloque recibe un Handle para el fencing (ver Handle#held?).
  def with_lock(key, ttl: DEFAULT_TTL)
    token = "#{Process.pid}-#{SecureRandom.hex(8)}"
    return NOT_ACQUIRED unless acquire(key, token, ttl)

    heartbeat = start_heartbeat(key, token, ttl)
    begin
      yield Handle.new(key, token)
    ensure
      heartbeat&.kill
      release(key, token)
    end
  end

  # ¿El valor del lock sigue siendo nuestro token? Base del fencing. Fail-CLOSED:
  # si Redis no responde, devolvemos false (mejor abortar la escritura crítica que
  # arriesgar un doble-procesamiento).
  def owner?(key, token)
    Redis::Alfred.get(key) == token
  rescue StandardError
    false
  end

  def acquire(key, token, ttl)
    Redis::Alfred.set(key, token, nx: true, ex: ttl)
  rescue StandardError
    # Ante fallo de Redis no bloqueamos el trabajo (fail-open, igual que el resto
    # del código): mejor correr que no correr. No hay heartbeat en ese caso.
    false
  end

  # Renueva el TTL periódicamente SOLO si seguimos siendo el dueño del lock.
  def start_heartbeat(key, token, ttl)
    interval = [ttl / HEARTBEAT_DIVISOR, 1].max
    Thread.new do
      loop do
        sleep(interval)
        break unless renew(key, token, ttl)
      end
    end
  end

  # Extiende el TTL si el valor sigue siendo nuestro token. Devuelve false si el
  # lock ya no es nuestro (paramos el heartbeat).
  def renew(key, token, ttl)
    Redis::Alfred.with do |conn|
      conn.watch(key) do
        if conn.get(key) == token
          conn.multi { |t| t.expire(key, ttl) }
          true
        else
          conn.unwatch
          false
        end
      end
    end
  rescue StandardError
    false
  end

  # Libera el lock solo si aún es nuestro (compare-and-delete atómico).
  def release(key, token)
    Redis::Alfred.delete_if_equals(key, token)
  rescue StandardError
    nil
  end
end
