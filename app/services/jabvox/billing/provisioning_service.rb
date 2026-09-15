# frozen_string_literal: true

# Aprovisiona una cuenta a partir de una transacción de pago YA APROBADA. Es idempotente:
# si la transacción ya está aprovisionada, no hace nada (no habilita tiempo dos veces).
#
# Reutiliza Jabvox::AccountProvisioningService (que ya crea cuenta+admin, activa módulos y
# features, y fija límites), y además:
#   - asigna el plan y calcula la fecha de expiración (renovación acumula si aún vigente),
#   - deja la transacción en estado provisioned,
#   - devuelve el set_password_url cuando se creó una cuenta nueva (para el correo).
class Jabvox::Billing::ProvisioningService
  def initialize(transaction)
    @tx = transaction
  end

  # Devuelve { account:, created_user:, set_password_url: } o levanta ProvisioningError.
  #
  # CONCURRENCIA: Bold reintenta los webhooks, así que dos ProvisioningJob pueden correr a
  # la vez para la misma transacción. Sin serializar, ambos pasarían el guard `provisioned?`
  # y aplicarían la vigencia DOS veces (doble mes). Tomamos un row-lock (with_lock) y
  # reevaluamos el estado DENTRO del lock: el segundo job verá `provisioned?` y hará replay.
  def call
    return replay if @tx.provisioned?

    @tx.with_lock do
      # Reevaluación dentro del lock: si otro job ya lo aprovisionó, no repetimos.
      return replay if @tx.provisioned?

      raise Jabvox::Billing::ProvisioningError, 'La transacción no está en un estado aprovisionable' unless @tx.retriable?

      plan = @tx.jabvox_plan
      raise Jabvox::Billing::ProvisioningError, 'La transacción no tiene plan asociado' if plan.nil?

      @tx.update!(attempts: @tx.attempts + 1)
      @tx.mark_provisioning!

      result = run_account_provisioning(plan)
      account = result[:account]
      apply_plan_period!(account, plan)
      apply_ai_budget!(account, plan)

      @tx.mark_provisioned!(account)
      { account: account, created_user: result[:created_user], set_password_url: result[:set_password_url] }
    end
  end

  private

  # Llama al servicio de aprovisionamiento base con los recursos del plan. Usa la
  # idempotency_key de la transacción para que un reintento no duplique la cuenta.
  #
  # Flujo "registro primero": si la transacción ya trae account_id (la cuenta se creó
  # en el registro), aprovisionamos SOBRE esa cuenta en vez de crear otra por email.
  def run_account_provisioning(plan)
    params = plan.provisioning_params(
      email: @tx.buyer_email,
      idempotency_key: @tx.idempotency_key,
      base_url: ENV.fetch('FRONTEND_URL', nil)
    )
    params[:account_id] = @tx.account_id if @tx.account_id.present?
    Jabvox::AccountProvisioningService.new(params).call
  rescue Jabvox::AccountProvisioningService::ProvisioningError => e
    raise Jabvox::Billing::ProvisioningError, e.message
  end

  # Asigna el plan y extiende la vigencia. Si la cuenta aún tiene plan vigente, la
  # renovación se ACUMULA desde la fecha de expiración; si no, desde hoy.
  def apply_plan_period!(account, plan)
    base = [account.jabvox_plan_expires_at, Time.current].compact.max
    account.update!(
      jabvox_plan_id: plan.id,
      jabvox_plan_expires_at: base + plan.duration_days.days,
      status: :active
    )
  end

  # Aplica el saldo de IA del plan a la cuenta (crea/actualiza el team en el proveedor). Es
  # BEST-EFFORT: si el proveedor no responde, NO revienta el aprovisionamiento del pago; el
  # error queda registrado y el worker mensual / un reintento posterior lo corrige. Solo actúa
  # si el proveedor está habilitado y el plan otorga saldo de IA.
  def apply_ai_budget!(account, plan)
    return unless JabvoxAiProviderConfig.instance.enabled_jabvox
    return if plan.ai_budget_cents_jabvox.to_i.zero?

    Jabvox::AiProvider::BalanceService.new(account).apply_plan!(plan, reference: @tx.idempotency_key)
  rescue StandardError => e
    Rails.logger.error("[Billing::Provisioning] saldo IA cuenta #{account.id}: #{e.class}: #{e.message}")
  end

  # Reconstruye el resultado sin volver a tocar nada (reintento sobre algo ya hecho).
  def replay
    { account: @tx.account, created_user: false, set_password_url: nil }
  end
end
