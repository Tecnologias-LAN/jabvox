# frozen_string_literal: true

# Middleware de servidor que mide run + latencia de cola alrededor de cada
# perform. Ver Jabvox::SidekiqMetrics.
class Jabvox::SidekiqMetricsMiddleware
  include Sidekiq::ServerMiddleware

  def call(_worker, job, queue)
    record_wait(job, queue)
    started = Jabvox::SidekiqMetrics.now_ms
    yield
  ensure
    elapsed = Jabvox::SidekiqMetrics.now_ms - started
    Jabvox::SidekiqMetrics.record(
      Jabvox::SidekiqMetrics.run_key(job['wrapped'] || job['class']), elapsed.round(1)
    )
  end

  private

  def record_wait(job, queue)
    enqueued_at = job['enqueued_at']
    return if enqueued_at.nil?

    wait_ms = ((Time.now.to_f - enqueued_at.to_f) * 1000).round(1)
    return if wait_ms.negative?

    Jabvox::SidekiqMetrics.record(Jabvox::SidekiqMetrics.wait_key(queue), wait_ms)
  end
end
