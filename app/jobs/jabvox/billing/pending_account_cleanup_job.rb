# frozen_string_literal: true

module Jabvox
  module Billing
    # Limpia cuentas creadas sin completar el pago tras el periodo de gracia configurable.
    # Se ejecuta diariamente y elimina cuentas en estado payment_pending que:
    #   1) Fueron creadas hace más de X días (JABVOX_PENDING_ACCOUNT_CLEANUP_DAYS)
    #   2) NO tienen transacciones de pago aprobadas/en proceso
    #
    # Esto evita basura de registros incompletos y libera recursos del servidor.
    class PendingAccountCleanupJob < ApplicationJob
      queue_as :jabvox_payments

      def perform
        config = JabvoxBillingConfig.instance
        cleanup_days = config.unpaid_account_cleanup_days
        cutoff = cleanup_days.days.ago

        # Cuentas en payment_pending SIN transacciones que hayan llegado a "pagado",
        # creadas antes del cutoff. IMPORTANTE: el whitelist incluye TODOS los estados
        # post-pago, incluido provisioning_failed: si el cliente PAGÓ pero el
        # aprovisionamiento falló, la cuenta NO debe borrarse (se resuelve por reintento
        # manual desde el super admin), o perderíamos una cuenta ya pagada.
        paid_statuses = %i[payment_approved provisioning provisioned provisioning_failed]
        unpaid_accounts = Account
          .where(status: :payment_pending)
          .where('created_at < ?', cutoff)
          .where.not(
            id: JabvoxProvisioningTransaction
              .where(status: paid_statuses)
              .select(:account_id)
          )

        count = 0
        unpaid_accounts.find_each do |account|
          Rails.logger.info("[PendingAccountCleanup] Eliminando cuenta #{account.id} (#{account.name}) sin pago tras #{cleanup_days} días")

          destroy_account_and_orphan_users(account)
          count += 1
        rescue StandardError => e
          Rails.logger.error("[PendingAccountCleanup] Error eliminando cuenta #{account.id}: #{e.message}")
        end

        Rails.logger.info("[PendingAccountCleanup] Proceso completado: #{count} cuentas eliminadas")
      end

      private

      # Elimina la cuenta y los usuarios que queden SIN ninguna otra cuenta. Dos trampas:
      #   1) account.users es has_many :through account_users; destroy_all ahí solo borra
      #      los vínculos, no los usuarios (quedarían huérfanos).
      #   2) account_users tiene dependent: :destroy_async, así que account.destroy! encola
      #      la baja de los vínculos en background -> chequear huérfanos justo después es
      #      una condición de carrera.
      # Por eso: capturamos los ids, borramos los account_users de ESTA cuenta de forma
      # síncrona, destruimos la cuenta y solo entonces borramos los usuarios ya sin cuenta.
      def destroy_account_and_orphan_users(account)
        user_ids = account.user_ids
        account.account_users.destroy_all
        account.destroy!

        User.where(id: user_ids)
            .where.missing(:account_users)
            .find_each(&:destroy!)
      end
    end
  end
end
