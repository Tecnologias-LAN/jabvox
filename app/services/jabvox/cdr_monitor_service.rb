# frozen_string_literal: true

# Estado del sincronizador de CDR para el dashboard de monitoreo (solo admin).
# Agrega los datos de auditoría (jabvox_cdr_sync_runs) + el estado actual.
module Jabvox
  class CdrMonitorService
    def initialize(account)
      @account = account
      @config = account.jabvox_cdr_config
    end

    def status # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      last = last_run
      today = JabvoxCdrSyncRun.for_account(@account.id).where('started_at >= ?', Time.zone.now.beginning_of_day)

      {
        configured: @config&.mysql_host.present?,
        # Estado del PBX según la última corrida (conectado / desconectado / desconocido).
        pbx_connected: last&.pbx_reachable,
        last_run_at: last&.started_at,
        last_run_status: last&.status,
        last_run_duration_ms: last&.duration_ms,
        last_error: last_error_message,
        last_error_at: last_error_run&.started_at,
        last_cursor: @config&.last_synced_calldate,
        # Promedio de duración de las últimas 20 corridas OK.
        avg_duration_ms: average_duration_ms,
        # Actividad de hoy.
        synced_today: today.sum('inserted_count + updated_count'),
        inserted_today: today.sum(:inserted_count),
        errors_today: today.sum(:error_count),
        runs_today: today.count,
        # Pendientes: cuánto falta por sincronizar desde el cursor (aprox por conteo local).
        total_local_records: JabvoxCdrRecord.for_account(@account.id).count,
        recent_runs: recent_runs
      }
    end

    private

    def last_run
      @last_run ||= JabvoxCdrSyncRun.for_account(@account.id).recent_first.first
    end

    def last_error_run
      @last_error_run ||= JabvoxCdrSyncRun.for_account(@account.id)
                                         .where.not(error_message: [nil, ''])
                                         .recent_first.first
    end

    def last_error_message
      last_error_run&.error_message
    end

    def average_duration_ms
      durations = JabvoxCdrSyncRun.for_account(@account.id)
                                 .where(status: 'ok')
                                 .recent_first.limit(20).pluck(:duration_ms)
      return 0 if durations.empty?

      (durations.sum.to_f / durations.size).round
    end

    def recent_runs
      JabvoxCdrSyncRun.for_account(@account.id).recent_first.limit(10).map do |r|
        {
          started_at: r.started_at,
          status: r.status,
          duration_ms: r.duration_ms,
          fetched: r.fetched_count,
          inserted: r.inserted_count,
          updated: r.updated_count,
          skipped: r.skipped_count,
          errors: r.error_count,
          pbx_reachable: r.pbx_reachable,
          error_message: r.error_message
        }
      end
    end
  end
end
