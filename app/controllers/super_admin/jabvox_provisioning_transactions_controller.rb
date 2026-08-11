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
end
