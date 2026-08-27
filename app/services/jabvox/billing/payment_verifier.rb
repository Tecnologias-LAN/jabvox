# frozen_string_literal: true

# Verifica ACTIVAMENTE contra la pasarela el estado de una transacción pendiente y, si el
# pago está realmente aprobado, la marca aprobada y encola el aprovisionamiento.
#
# Es la red de seguridad para cuando el WEBHOOK no llega (sandbox, red, config): al volver
# el usuario del checkout, la app le pregunta a la pasarela "¿este pago se aprobó?" y actúa
# solo si la pasarela lo confirma. NUNCA confía en el navegador: la fuente de verdad es la
# consulta server-to-server a la pasarela (misma garantía que el webhook firmado).
class Jabvox::Billing::PaymentVerifier
  Result = Struct.new(:approved, :status, keyword_init: true) do
    def approved?
      approved
    end
  end

  def initialize(transaction)
    @tx = transaction
  end

  # Devuelve Result(approved:, status:). Idempotente: si ya estaba aprobada/aprovisionada,
  # no vuelve a consultar ni duplica el trabajo.
  def call
    return Result.new(approved: true, status: @tx.status) if @tx.already_provisioned? || @tx.payment_approved?

    # Bold consulta el estado por la REFERENCIA EXTERNA (nuestra idempotency_key, guardada
    # en gateway_reference) vía el servicio de fallback del webhook.
    reference = @tx.gateway_reference.presence || @tx.idempotency_key
    return Result.new(approved: false, status: @tx.status) if reference.blank?

    gateway = Jabvox::Billing::Gateways::Base.for_active
    return Result.new(approved: false, status: 'no_gateway') if gateway.nil?

    status = gateway.fetch_payment_status(reference)
    return Result.new(approved: false, status: status[:status]) unless status[:approved]
    return Result.new(approved: false, status: 'amount_mismatch') if amount_mismatch?(status)

    approve_and_provision!(status)
    Result.new(approved: true, status: 'payment_approved')
  rescue Jabvox::Billing::Gateways::GatewayError => e
    Rails.logger.warn("[PaymentVerifier] tx=#{@tx.id}: #{e.message}")
    Result.new(approved: false, status: 'gateway_error')
  end

  private

  # Mismo criterio que el webhook: el monto real debe coincidir con el de la transacción.
  def amount_mismatch?(status)
    expected = @tx.amount_cents || @tx.jabvox_plan&.price_cents
    return false if expected.blank? || status[:amount_cents].nil?

    status[:amount_cents].to_i != expected.to_i
  end

  def approve_and_provision!(status)
    @tx.mark_payment_approved!(reference: @tx.gateway_reference, amount_cents: status[:amount_cents] || @tx.amount_cents)
    Jabvox::Billing::ProvisioningJob.perform_later(@tx.id)
  end
end
