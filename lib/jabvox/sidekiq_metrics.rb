# frozen_string_literal: true

# Instrumentación de Sidekiq para dimensionar a escala (Paso 0 del plan de 1000
# cuentas). Por cada job ejecutado registra dos métricas:
#
#   run  — cuánto tarda el job en EJECUTARSE (perform). p50/p95/p99 alimentan la
#          condición de supervivencia por cola.
#   wait — LATENCIA DE COLA: cuánto esperó el job encolado antes de empezar
#          (now - enqueued_at). Métrica de VEREDICTO del soak: si sube monótona,
#          esa cola no drena.
#
# Reservoir: lista Redis acotada a SAMPLE_CAP por métrica, con TTL. Da percentiles
# exactos sobre la ventana reciente con un par de comandos Redis por job.
# Se activa con ENABLE_JABVOX_SIDEKIQ_METRICS=true. Lee con `rake jabvox:sidekiq_metrics`.
module Jabvox::SidekiqMetrics
  SAMPLE_CAP = 2000
  TTL = 3600
  RUN_PREFIX = 'jabvox:metrics:run'
  WAIT_PREFIX = 'jabvox:metrics:wait'

  module_function

  def enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_JABVOX_SIDEKIQ_METRICS', false))
  end

  def now_ms
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
  end

  def run_key(job_class)
    "#{RUN_PREFIX}:#{job_class}"
  end

  def wait_key(queue)
    "#{WAIT_PREFIX}:#{queue}"
  end

  def record(key, value_ms)
    Redis::Alfred.with do |conn|
      conn.pipelined do |p|
        p.lpush(key, value_ms)
        p.ltrim(key, 0, SAMPLE_CAP - 1)
        p.expire(key, TTL)
      end
    end
  rescue StandardError
    nil # medir nunca debe romper un job
  end

  def samples(key)
    Redis::Alfred.with { |conn| conn.lrange(key, 0, -1) }.map(&:to_f)
  rescue StandardError
    []
  end

  def keys(prefix)
    found = []
    Redis::Alfred.with { |conn| conn.scan_each(match: "#{prefix}:*", count: 200) { |k| found << k } }
    found
  rescue StandardError
    []
  end

  def percentile(sorted, pct)
    return 0.0 if sorted.empty?

    rank = (pct / 100.0) * (sorted.size - 1)
    lower = sorted[rank.floor]
    upper = sorted[rank.ceil]
    (lower + ((upper - lower) * (rank - rank.floor))).round(1)
  end

  def summary(key)
    s = samples(key).sort
    { count: s.size, p50: percentile(s, 50), p95: percentile(s, 95),
      p99: percentile(s, 99), max: (s.last || 0).round(1) }
  end

  def reset!
    (keys(RUN_PREFIX) + keys(WAIT_PREFIX)).each { |k| Redis::Alfred.with { |c| c.del(k) } }
  end
end
