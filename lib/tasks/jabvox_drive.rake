# frozen_string_literal: true

# Tareas de mantenimiento y diagnóstico del módulo jabvox-drive.
#
# Pensadas para operar la cola DURABLE (JabvoxDrivePendingOperation) a mano: forzar
# el procesamiento de pendientes, reconciliar cuota/huérfanos, y reencolar
# operaciones que agotaron reintentos (failed -> pending).
#
#   rake jabvox:drive:process_pending
#   rake jabvox:drive:reconcile[37]
#   rake jabvox:drive:retry_failed[37]
#
# rubocop:disable Metrics/BlockLength
namespace :jabvox do
  namespace :drive do
    desc 'Procesa YA las operaciones pendientes due (reencola el job adecuado por kind)'
    task process_pending: :environment do
      due = JabvoxDrivePendingOperation.due
      count = due.count
      puts "[jabvox:drive] operaciones due: #{count}"
      Jabvox::Drive::PendingOperationRetryJob.perform_now
      puts "[jabvox:drive] despacho completado (#{count} operaciones reencoladas)"
    end

    desc 'Reconciliación/huérfanos del Drive. Uso: reconcile[ACCOUNT_ID] (vacío = todas)'
    task :reconcile, [:account_id] => :environment do |_t, args|
      accounts = resolve_accounts(args[:account_id])
      puts "[jabvox:drive] reconciliando #{accounts.size} cuenta(s)"
      accounts.each do |account|
        Jabvox::Drive::ReconciliationService.new(account).regularize!
        Jabvox::Drive::ReconciliationService.new(account).reconcile!
        puts "  - cuenta #{account.id}: regularize! + reconcile! OK"
      rescue StandardError => e
        puts "  - cuenta #{account.id}: ERROR #{e.class}: #{e.message}"
      end
    end

    desc 'Reencola operaciones failed -> pending. Uso: retry_failed[ACCOUNT_ID] (vacío = todas)'
    task :retry_failed, [:account_id] => :environment do |_t, args|
      scope = JabvoxDrivePendingOperation.where(status: :failed)
      scope = scope.where(account_id: args[:account_id]) if args[:account_id].present?

      total = 0
      scope.find_each do |operation|
        operation.update!(status: :pending, attempts: 0, last_error: nil, next_attempt_at: Time.current)
        total += 1
      end
      puts "[jabvox:drive] reencoladas failed->pending: #{total}"
      puts '[jabvox:drive] ejecuta `rake jabvox:drive:process_pending` para despacharlas ahora'
    end

    desc 'Aprovisiona aislamiento duro en MinIO (usuario+policy por prefijo). Uso: provision[ACCOUNT_ID]'
    task :provision, [:account_id] => :environment do |_t, args|
      unless Jabvox::Drive::ProvisioningService.enabled?
        puts '[jabvox:drive] JABVOX_DRIVE_PROVISION_PER_ACCOUNT=false; nada que hacer.'
        next
      end
      accounts = resolve_accounts(args[:account_id])
      puts "[jabvox:drive] aprovisionando MinIO para #{accounts.size} cuenta(s)"
      accounts.each do |account|
        ok = Jabvox::Drive::ProvisioningService.new(account).provision!
        puts "  cuenta #{account.id}: #{ok ? 'OK' : 'FALLÓ (ver logs)'}"
      end
    end

    def resolve_accounts(account_id)
      if account_id.present?
        Account.where(id: account_id).to_a
      else
        Account.where(jabvox_drive_enabled_jabvox: true).to_a
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
