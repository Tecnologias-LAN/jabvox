# frozen_string_literal: true

namespace :jabvox do
  desc 'Reporta p50/p95/p99 de duración (run) y latencia de cola (wait) de Sidekiq. ' \
       'Requiere ENABLE_JABVOX_SIDEKIQ_METRICS=true en los workers.'
  task sidekiq_metrics: :environment do
    print_section = lambda do |title, prefix|
      puts "\n== #{title} =="
      keys = Jabvox::SidekiqMetrics.keys(prefix).sort
      if keys.empty?
        puts '  (sin datos — ¿ENABLE_JABVOX_SIDEKIQ_METRICS=true y jobs ejecutados?)'
      else
        keys.each do |k|
          label = k.sub("#{prefix}:", '')
          s = Jabvox::SidekiqMetrics.summary(k)
          puts format('  %<label>-45s n=%<count>-6d p50=%<p50>-8.1f p95=%<p95>-8.1f p99=%<p99>-8.1f max=%<max>-8.1f',
                      label: label, count: s[:count], p50: s[:p50], p95: s[:p95], p99: s[:p99], max: s[:max])
        end
      end
    end

    print_section.call('DURACIÓN DE JOB (ms) — run', Jabvox::SidekiqMetrics::RUN_PREFIX)
    print_section.call('LATENCIA DE COLA (ms) — wait [MÉTRICA DE VEREDICTO]', Jabvox::SidekiqMetrics::WAIT_PREFIX)
    puts "\nSi la LATENCIA DE COLA de una cola sube monótona en el tiempo, esa cola no drena."
  end

  desc 'Limpia las métricas de Sidekiq acumuladas (reservoirs run/wait).'
  task sidekiq_metrics_reset: :environment do
    Jabvox::SidekiqMetrics.reset!
    puts 'Métricas de Sidekiq limpiadas.'
  end
end
