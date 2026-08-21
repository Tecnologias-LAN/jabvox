# frozen_string_literal: true

# Panel Super Admin: visual de estados pago↔aprovisionamiento (solo lectura) + reintento
# manual del aprovisionamiento para las transacciones marcadas como fallidas.
class SuperAdmin::JabvoxProvisioningTransactionsController < SuperAdmin::ApplicationController
  # Reencola el aprovisionamiento de una transacción (fallida o aprobada). Idempotente:
  # el servicio no habilita tiempo dos veces si ya estaba aprovisionada.
  def retry_provisioning
    tx = JabvoxProvisioningTransaction.find(params[:id])

    unless tx.retriable?
      return redirect_to [:super_admin, tx],
                         alert: I18n.t('jabvox.billing.transactions.not_retriable', status: tx.status)
    end

    Jabvox::Billing::ProvisioningJob.perform_later(tx.id)
    redirect_to [:super_admin, tx], notice: I18n.t('jabvox.billing.transactions.retry_enqueued')
  end

  # Aprobación MANUAL: marca el pago aprobado y encola el aprovisionamiento. SOLO para
  # transacciones de PRUEBA (sandbox), donde el webhook no se envía. En PRODUCCIÓN se
  # rechaza: un pago real solo lo confirma la pasarela (evita activar cuentas sin pagar).
  # Solo el super admin (autenticado por SuperAdmin::ApplicationController) puede llegar aquí.
  def mark_paid_manually
    tx = JabvoxProvisioningTransaction.find(params[:id])

    unless tx.sandbox?
      return redirect_to [:super_admin, tx],
                         alert: 'Solo se pueden aprobar manualmente transacciones de PRUEBA (sandbox). ' \
                                'Un pago de producción se confirma únicamente por la pasarela.'
    end

    if tx.already_provisioned?
      return redirect_to [:super_admin, tx], notice: 'La transacción ya estaba aprovisionada.'
    end

    tx.mark_payment_approved!
    Jabvox::Billing::ProvisioningJob.perform_later(tx.id)
    redirect_to [:super_admin, tx], notice: 'Pago de PRUEBA aprobado y aprovisionamiento encolado.'
  end
end
