# frozen_string_literal: true

# Regularización de cuota del Drive para una cuenta.
#
# Se dispara cuando se AMPLÍA la cuota de una cuenta (cambio de plan / aumento de
# storage_gb): los objetos que habían ido al bucket de overflow (por cuota llena)
# se mueven al bucket principal y vuelven a ser visibles. La lógica concreta
# (mover overflow->principal, recalcular contadores, limpiar huérfanos) vive en
# Jabvox::Drive::ReconciliationService.
#
# Este job es el disparador asíncrono (cola jabvox_drive): resuelve la cuenta y
# delega. Es idempotente y seguro de re-ejecutar (regularize! lo es).
class Jabvox::Drive::QuotaRegularizationJob < ApplicationJob
  queue_as :jabvox_drive

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.nil?

    Jabvox::Drive::ReconciliationService.new(account).regularize!
  end
end
