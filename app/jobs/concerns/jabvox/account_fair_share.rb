# frozen_string_literal: true

# Fairness por cuenta para jobs de fan-out: limita cuántos jobs de UNA cuenta corren
# EN VUELO a la vez en su worker, para que una cuenta con miles de tareas no acapare
# todos los slots y ahogue a las demás (head-of-line blocking). Los que exceden el cupo
# NO bloquean el worker: se re-encolan con un pequeño delay hasta que se libera un slot.
#
# Uso en un job de fan-out por cuenta:
#
#   class MiJob < ApplicationJob
#     include Jabvox::AccountFairShare
#     fair_share_limit 10                 # opcional; default 10
#     fair_share_env 'JABVOX_MI_MAX_INFLIGHT_PER_ACCOUNT'  # opcional; override por ENV
#
#     def perform(record_id)
#       record = Model.find_by(id: record_id)
#       return if record.nil?
#       with_account_fair_share(record.account_id) do
#         # ...trabajo pesado por-cuenta...
#       end
#     end
#   end
#
# with_account_fair_share re-encola el MISMO job (mismos args) si no hay cupo, así que el
# job debe ser idempotente y su perform recibir los args que permitan reintentarlo igual.
module Jabvox
  module AccountFairShare
    extend ActiveSupport::Concern

    DEFAULT_LIMIT = 10
    INFLIGHT_TTL = 30 * 60 # s; red de seguridad si un proceso muere sin liberar
    REQUEUE_DELAY = 20 # s

    class_methods do
      def fair_share_limit(value)
        @fair_share_limit = value.to_i
      end

      def fair_share_env(var)
        @fair_share_env = var.to_s
      end

      def resolved_fair_share_limit
        env_val = @fair_share_env && ENV[@fair_share_env].presence
        (env_val || @fair_share_limit || DEFAULT_LIMIT).to_i
      end
    end

    # Ejecuta el bloque solo si la cuenta tiene un slot libre; si no, re-encola este job
    # (mismos args) con delay y no ejecuta. Devuelve :requeued si difirió.
    def with_account_fair_share(account_id)
      return yield if account_id.blank? # sin cuenta: sin límite (no debería ocurrir)

      unless acquire_account_slot(account_id)
        self.class.set(wait: REQUEUE_DELAY.seconds).perform_later(*arguments)
        return :requeued
      end

      begin
        yield
      ensure
        release_account_slot(account_id)
      end
    end

    private

    def account_slot_key(account_id)
      "jabvox_fairshare_#{self.class.name.underscore.tr('/', '_')}_#{account_id}"
    end

    def acquire_account_slot(account_id)
      key = account_slot_key(account_id)
      count = Redis::Alfred.incr(key)
      Redis::Alfred.expire(key, INFLIGHT_TTL) if count == 1
      return true if count <= self.class.resolved_fair_share_limit

      Redis::Alfred.decr(key)
      false
    rescue StandardError => e
      # Ante fallo de Redis, no bloqueamos el procesamiento (mejor procesar que atascar).
      Rails.logger.warn("[AccountFairShare] #{self.class.name} Redis error, procesando igual | #{e.message}")
      true
    end

    def release_account_slot(account_id)
      Redis::Alfred.decr(account_slot_key(account_id))
    rescue StandardError => e
      Rails.logger.warn("[AccountFairShare] #{self.class.name} release error | #{e.message}")
    end
  end
end
