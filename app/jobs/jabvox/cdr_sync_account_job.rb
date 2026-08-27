# frozen_string_literal: true

# Sincroniza el CDR del PBX de UNA sola cuenta (fan-out desde CdrSyncJob). Aísla
# el trabajo MySQL por cuenta: rescue propio y caché de PBX caído para no gastar
# el connect-timeout contra servidores apagados.
class Jabvox::CdrSyncAccountJob < ApplicationJob
  queue_as :jabvox_cdr

  UNREACHABLE_TTL = 5.minutes.to_i

  def perform(account_id)
    return if pbx_unreachable_cached?(account_id)

    account = Account.joins(:jabvox_cdr_config).find_by(id: account_id)
    return if account.nil?

    result = Jabvox::CdrSyncService.sync_account(account)
    mark_unreachable(account_id) if result[:reachable] == false
    if (result[:inserted].to_i + result[:updated].to_i).positive?
      Rails.logger.info("[CdrSync] cuenta=#{account_id} +#{result[:inserted]} ~#{result[:updated]}")
    end
  rescue StandardError => e
    Rails.logger.error("[CdrSyncAccountJob] cuenta=#{account_id} #{e.class}: #{e.message}")
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
    Rails.logger.warn("[CdrSyncAccountJob] no se pudo cachear PBX caído cuenta=#{account_id} | #{e.message}")
  end
end
