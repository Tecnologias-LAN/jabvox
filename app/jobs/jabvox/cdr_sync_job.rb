# frozen_string_literal: true

# Dispatcher del CDR sync (cron cada 1 min): encola un CdrSyncAccountJob por
# cuenta con CDR configurado, en la cola aislada jabvox_cdr.
#
# NOTA sobre O(activas): el "CDR nuevo" vive en el MySQL del PBX (remoto), no en
# Postgres, así que NO se puede saber desde aquí, sin abrir el PBX, qué cuenta
# tiene llamadas nuevas. Lo que sí evitamos es encolar cuentas SIN PBX
# configurado (mysql_host vacío): el job por-cuenta las saltaba igual, pero ya
# después de encolar. Filtrarlas aquí reduce el fan-out real. La caché de "PBX no
# responde" (en el job por-cuenta) corta las que están apagadas.
class Jabvox::CdrSyncJob < ApplicationJob
  queue_as :jabvox_cdr

  # Si la cola aún arrastra trabajo de la corrida anterior, saltamos esta pasada.
  BACKLOG_CEILING = 1000

  def perform
    if queue_backlogged?
      Rails.logger.warn('[CdrSync] backlog alto en jabvox_cdr; salto esta corrida')
      return
    end

    enqueued = 0
    JabvoxCdrConfig.where.not(mysql_host: '').select(:account_id).find_each do |config|
      Jabvox::CdrSyncAccountJob.perform_later(config.account_id)
      enqueued += 1
    rescue StandardError => e
      Rails.logger.error("[CdrSync] no se pudo encolar cuenta=#{config.account_id} #{e.class}: #{e.message}")
    end
    Rails.logger.info("[CdrSync] syncs encolados: #{enqueued}") if enqueued.positive?
  end

  private

  def queue_backlogged?
    Sidekiq::Queue.new('jabvox_cdr').size > BACKLOG_CEILING
  rescue StandardError
    false
  end
end
