# frozen_string_literal: true

# Drenador de exports por CUENTA. Sustituye el rebote (re-encolado con wait) del
# WriteJob por el patrón correcto de "vecino ruidoso":
#
#   - El concern ExportableToExternalDb añade cada (modelo,id) a un Redis Set por
#     cuenta (dedup: un registro tocado N veces ocupa 1 miembro = coalescing) y se
#     asegura de que haya UN solo DrainJob encolado para esa cuenta (lock enqueue).
#   - Este job saca del Set en LOTES (BATCH_SIZE), exporta cada registro con
#     RowExporterService, y se re-encola solo si quedan pendientes. Así una cuenta
#     con una avalancha de 50k NO genera 50k jobs ni un busy-loop: es un job por
#     cuenta procesando su backlog en tandas, y las demás cuentas tienen su propio
#     DrainJob compitiendo en igualdad por los slots de la cola (fairness real).
#
# Idempotente: exporta el estado ACTUAL del registro; reprocesar es inocuo.
# Circuit-breaker: si la BD externa de la cuenta cayó, corta el lote y reintenta
# más tarde sin martillar (misma marca unreachable que usaba el WriteJob).
class Jabvox::ExternalExport::DrainJob < ApplicationJob
  queue_as :jabvox_export

  BATCH_SIZE = 200          # registros por corrida del drenador
  UNREACHABLE_TTL = 60      # s; salta la cuenta si su BD externa cayó
  REQUEUE_WAIT = 5          # s; espera al reintentar cuando la BD está caída

  retry_on Jabvox::ExternalExport::WriteAdapter::ConnectionError,
           wait: :polynomially_longer, attempts: 3

  def self.pending_set_key(account_id)
    "jabvox_export_pending_set_#{account_id}"
  end

  def self.enqueue_lock_key(account_id)
    "jabvox_export_drain_enqueued_#{account_id}"
  end

  # Encola UN drenador por cuenta: el lock (SET NX EX) evita que N commits encolen
  # N drenadores. Se libera al empezar el perform. Devuelve true si encoló.
  def self.ensure_enqueued(account_id)
    return false unless Redis::Alfred.set(enqueue_lock_key(account_id), 1, nx: true, ex: 3600)

    perform_later(account_id)
    true
  rescue StandardError
    # Ante fallo de Redis, encolamos igual (mejor de más que perder el export).
    perform_later(account_id)
    true
  end

  def perform(account_id)
    # Liberamos el lock de encolado: a partir de aquí, nuevos commits pueden encolar
    # el siguiente drenador (que procesará lo que llegue después de este lote).
    Redis::Alfred.delete(self.class.enqueue_lock_key(account_id))

    account = Account.find_by(id: account_id)
    return unless account&.feature_enabled?('jabvox_data_export')

    target = account.jabvox_export_targets.active.first
    return unless target
    return if target_unreachable?(account_id) && requeue_later(account_id)

    drain_batch(account, target, account_id)
  end

  private

  def drain_batch(account, target, account_id)
    members = pop_batch(account_id)
    return if members.empty?

    members.each { |member| export_member(account, target, member) }
    # ¿Quedan pendientes? Encola el siguiente lote (otro job, sin busy-loop).
    self.class.ensure_enqueued(account_id) if pending?(account_id)
  end

  # Exporta un miembro "model_name:record_id" con el scope de la cuenta.
  def export_member(account, target, member)
    # member = "Model::Name:record_id"; el id es el último segmento (rpartition
    # respeta los "::" del nombre de clase).
    model_name, _, record_id = member.rpartition(':')
    record = resolve_record(account, target, model_name, record_id)
    return unless record

    Jabvox::ExternalExport::RowExporterService.new(target).export(record)
  rescue Jabvox::ExternalExport::WriteAdapter::ConnectionError
    mark_unreachable(account.id)
    # Devolvemos el miembro al Set para reintentarlo cuando la BD vuelva.
    Redis::Alfred.sadd(self.class.pending_set_key(account.id), member)
    raise
  rescue StandardError => e
    Rails.logger.error("[ExternalExport::Drain] #{member} #{e.class}: #{e.message}")
  end

  def resolve_record(account, target, model_name, record_id)
    klass = model_name.safe_constantize
    return unless klass

    model = klass.respond_to?(:base_class) ? klass.base_class : klass
    allowed = Jabvox::ExternalExport::Catalog.exportable_models(account, selected_groups: target.selected_modules)
    return unless allowed.include?(model)

    Jabvox::ExternalExport::Catalog.account_scope(model, account.id).find_by(id: record_id)
  end

  # Saca hasta BATCH_SIZE miembros del Set (SPOP atómico: dos drenadores no toman
  # el mismo). Ante fallo de Redis, lote vacío (no rompe).
  def pop_batch(account_id)
    Redis::Alfred.with { |c| Array(c.spop(self.class.pending_set_key(account_id), BATCH_SIZE)) }
  rescue StandardError
    []
  end

  def pending?(account_id)
    Redis::Alfred.with { |c| c.scard(self.class.pending_set_key(account_id)) }.to_i.positive?
  rescue StandardError
    false
  end

  def requeue_later(account_id)
    self.class.set(wait: REQUEUE_WAIT.seconds).perform_later(account_id)
    true
  end

  def unreachable_key(account_id)
    "jabvox_export_db_unreachable_#{account_id}"
  end

  def target_unreachable?(account_id)
    Redis::Alfred.get(unreachable_key(account_id)).present?
  rescue StandardError
    false
  end

  def mark_unreachable(account_id)
    Redis::Alfred.set(unreachable_key(account_id), Time.current.to_i, ex: UNREACHABLE_TTL)
  rescue StandardError
    nil
  end
end
