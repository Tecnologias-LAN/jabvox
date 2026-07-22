# frozen_string_literal: true

# Sincroniza el CDR del PBX hacia la tabla local jabvox_cdr_records (cron).
# Recorre cada cuenta con CDR configurado; un fallo en una cuenta NUNCA afecta a
# las demás (cada una en su propio rescue). Cachea las cuentas cuyo PBX no
# responde para no gastar el connect-timeout en cada corrida.
class Jabvox::CdrSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  UNREACHABLE_TTL = 5.minutes.to_i

  def perform
    Account.joins(:jabvox_cdr_config).find_each do |account|
      next if pbx_unreachable_cached?(account.id)

      result = Jabvox::CdrSyncService.sync_account(account)
      mark_unreachable(account.id) if result[:reachable] == false
      if (result[:inserted].to_i + result[:updated].to_i).positive?
        Rails.logger.info("[CdrSync] cuenta=#{account.id} +#{result[:inserted]} ~#{result[:updated]}")
      end
    rescue StandardError => e
      # Aislamiento estricto: el error de una cuenta no corta el bucle.
      Rails.logger.error("[CdrSyncJob] cuenta=#{account.id} #{e.class}: #{e.message}")
    end
  end

  private

  def unreachable_key(account_id)
    "jabvox_cdr_pbx_unreachable_#{account_id}"
  end

  def pbx_unreachable_cached?(account_id)
    Redis::Alfred.get(unreachable_key(account_id)).present?
  rescue StandardError
    false
  end

  def mark_unreachable(account_id)
    Redis::Alfred.set(unreachable_key(account_id), Time.current.to_i, ex: UNREACHABLE_TTL)
  rescue StandardError => e
    Rails.logger.warn("[CdrSyncJob] no se pudo cachear PBX caído cuenta=#{account_id} | #{e.message}")
  end
end
