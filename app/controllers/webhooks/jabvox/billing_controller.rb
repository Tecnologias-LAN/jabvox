# frozen_string_literal: true

# Webhook de la pasarela de pago (Bold/Wompi/Mono) y resolución del token de checkout
# para la web. Es un endpoint PÚBLICO (ActionController::API, sin CSRF) pero blindado:
#
#   1) Verifica la FIRMA del webhook (rechaza cualquier payload manipulado o sin firma).
#   2) Exige TIPO de evento aprobado y que el MONTO coincida con el precio del plan.
#   3) Doble verificación contra el estado real de la pasarela cuando esté disponible.
#   4) Solo entonces marca aprobado (idempotente por idempotency_key) y encola el
#      aprovisionamiento. Así no entran ni se pueden fabricar pagos falsos.
#
# Rutas:
#   POST /webhooks/jabvox/billing/:gateway   -> process_payload
#   POST /webhooks/jabvox/billing/resolve    -> resolve_token (para la web de cobro)
class Webhooks::Jabvox::BillingController < ActionController::API
  before_action :set_gateway, only: :process_payload

  def process_payload
    raw = request.raw_post

    # 1) FIRMA: rechaza cualquier webhook no firmado o manipulado. Sin esto no seguimos.
    unless @gateway.verify_webhook_signature(request, raw)
      Rails.logger.warn("[BillingWebhook] firma inválida (gateway=#{params[:gateway]})")
      return head :unauthorized
    end

    event = parse_event(raw)
    return head :unprocessable_entity if event[:reference].blank?

    process_event(event)
    head :ok
  rescue Jabvox::Billing::Gateways::GatewayError => e
    Rails.logger.error("[BillingWebhook] #{e.message}")
    head :unprocessable_entity
  end

  # La web NO decodifica el token: lo envía aquí y recibe los datos públicos del plan y
  # una idempotency_key para crear el checkout. Requiere el token interno app↔web.
  def resolve_token
    return head :unauthorized unless valid_internal_auth?

    decoded = Jabvox::Billing::CheckoutTokenService.decode(params[:token].to_s)
    plan = JabvoxPlan.sellable.find_by(id: decoded[:plan_id])
    account = Account.find_by(id: decoded[:account_id])
    return head :unprocessable_entity if plan.nil?

    render json: resolve_payload(decoded, plan, account)
  rescue Jabvox::Billing::CheckoutTokenError => e
    render json: { error: e.message }, status: :unauthorized
  end

  # La web pide crear el checkout: validamos el token, registramos la transacción
  # payment_pending (fuente de verdad en la app) y devolvemos la checkout_url de la
  # pasarela activa. Requiere el token interno app↔web.
  def create_checkout
    return head :unauthorized unless valid_internal_auth?

    decoded = Jabvox::Billing::CheckoutTokenService.decode(params[:token].to_s)
    plan = JabvoxPlan.sellable.find_by(id: decoded[:plan_id])
    return head :unprocessable_entity if plan.nil?

    gateway = Jabvox::Billing::Gateways::Base.for_active
    return render json: { error: 'no_active_gateway' }, status: :unprocessable_entity if gateway.nil?

    render json: perform_checkout(decoded, plan, gateway)
  rescue Jabvox::Billing::CheckoutTokenError => e
    render json: { error: e.message }, status: :unauthorized
  rescue Jabvox::Billing::Gateways::GatewayError => e
    Rails.logger.error("[BillingCheckout] #{e.message}")
    render json: { error: 'gateway_error' }, status: :bad_gateway
  end

  private

  def set_gateway
    cfg = JabvoxPaymentGatewayConfig.find_by(provider: params[:gateway], active: true)
    return head :not_found if cfg.nil?

    @gateway = Jabvox::Billing::Gateways::Base.build(cfg)
  end

  # Interpreta el evento YA VERIFICADO por firma (el adaptador sabe leer su formato).
  def parse_event(raw)
    payload = JSON.parse(raw.presence || '{}')
    @gateway.parse_webhook_event(payload)
  rescue JSON::ParserError
    { reference: nil }
  end

  # Avanza la máquina de estados de la transacción a partir del evento firmado.
  # Defensa en profundidad contra pagos falsos/alterados:
  #   a) la firma ya garantizó autenticidad (arriba),
  #   b) el TIPO debe ser aprobado,
  #   c) el MONTO del evento debe coincidir con el precio del plan de la transacción,
  #   d) si Bold expone estado real, se consulta como doble verificación.
  def process_event(event)
    txn = find_transaction(event[:reference])
    return if txn.nil? || txn.already_provisioned?

    txn.update!(payload: safe_payload(event))
    approve_or_reject(txn, event)
  end

  # Aplica las validaciones de seguridad en orden y aprueba o rechaza la transacción.
  def approve_or_reject(txn, event)
    return txn.mark_payment_rejected!(reason: "Pago no aprobado: #{event[:status]}", invalid: true) unless event[:approved]
    return txn.mark_payment_rejected!(reason: 'Monto no coincide con el plan', invalid: true) if amount_mismatch?(txn, event)
    return unless double_check_ok?(txn, event)

    txn.mark_payment_approved!(reference: event[:payment_id] || event[:reference],
                               amount_cents: event[:amount_cents] || txn.amount_cents)
    Jabvox::Billing::ProvisioningJob.perform_later(txn.id)
  end

  def find_transaction(reference)
    JabvoxProvisioningTransaction.find_by(idempotency_key: reference) ||
      JabvoxProvisioningTransaction.find_by(gateway_reference: reference)
  end

  # El monto pagado debe igualar el monto de la transacción. Puede incluir extras por
  # cuenta (agentes, bandejas, storage, etc.), así que se valida contra el monto guardado
  # en la transacción (no contra el plan base).
  #
  # SEGURIDAD: si esperamos un monto y el evento NO lo trae, es un MISMATCH (rechazar).
  # Antes se dejaba pasar el evento sin monto, lo que permitía aprobar un pago sin validar
  # el importe. Solo se omite la validación cuando la transacción no tiene monto esperado
  # (caso degenerado que no debería ocurrir con planes reales).
  def amount_mismatch?(txn, event)
    expected = txn.amount_cents || txn.jabvox_plan&.price_cents
    return false if expected.blank? # sin monto esperado no hay nada que comparar

    event[:amount_cents].nil? || event[:amount_cents].to_i != expected.to_i
  end

  # Doble verificación con el estado real de la pasarela cuando esté disponible. Se
  # consulta preferentemente por el payment_id del evento (identificador real del pago en
  # la pasarela); si no viene, se cae a la referencia del link. Si la consulta devuelve
  # UNKNOWN (no disponible), nos apoyamos en la firma+tipo+monto ya validados.
  def double_check_ok?(txn, event)
    lookup = event[:payment_id].presence || txn.gateway_reference.presence || event[:reference]
    status = @gateway.fetch_payment_status(lookup)
    return true if status[:status] == 'UNKNOWN'

    unless status[:approved]
      txn.mark_payment_rejected!(reason: "Estado real no aprobado: #{status[:status]}", invalid: true)
      return false
    end
    true
  end

  # Solo datos NO sensibles en la transacción (nunca tokens/tarjetas/PII cruda).
  def safe_payload(event)
    { last_status: event[:status], payment_id: event[:payment_id], checked_at: Time.current.iso8601 }.compact
  end

  # Crea la transacción pendiente, pide la URL a la pasarela y devuelve el payload JSON.
  def perform_checkout(decoded, plan, gateway)
    txn = build_pending_transaction(decoded, plan, gateway)
    checkout = create_gateway_checkout(gateway, plan, txn, decoded)
    txn.update!(gateway_reference: checkout[:reference])
    { checkout_url: checkout[:checkout_url], idempotency_key: txn.idempotency_key }
  end

  # Crea la transacción en estado payment_pending (idempotency_key = referencia única).
  def build_pending_transaction(decoded, plan, gateway)
    account = Account.find_by(id: decoded[:account_id])
    JabvoxProvisioningTransaction.create!(
      account: account,
      jabvox_plan: plan,
      buyer_email: account&.administrators&.first&.email,
      gateway: gateway.provider,
      idempotency_key: SecureRandom.uuid,
      amount_cents: checkout_amount_cents(account, plan),
      currency: plan.currency,
      status: :payment_pending
    )
  end

  def create_gateway_checkout(gateway, plan, txn, decoded)
    gateway.create_checkout(
      amount_cents: txn.amount_cents,
      currency: plan.currency,
      reference: txn.idempotency_key,
      metadata: {
        account_id: decoded[:account_id], plan_id: plan.id,
        idempotency_key: txn.idempotency_key
      }
    )
  end

  def resolve_payload(decoded, plan, account)
    {
      account_id: decoded[:account_id],
      account_name: account&.name,
      plan: {
        id: plan.id,
        name: plan.name,
        price_cents: plan.price_cents,
        extra_price_cents: account&.billable_extra_cents.to_i,
        total_price_cents: checkout_amount_cents(account, plan),
        currency: plan.currency
      },
      idempotency_key: SecureRandom.uuid,
      gateway: JabvoxPaymentGatewayConfig.active_gateway&.provider
    }
  end

  def checkout_amount_cents(account, plan)
    return plan.price_cents if account.nil?

    account.billable_total_cents
  end

  # Autenticación del canal app↔web mediante un secreto compartido en cabecera.
  def valid_internal_auth?
    expected = ENV.fetch('JABVOX_WEB_INTERNAL_TOKEN', nil)
    return false if expected.blank?

    ActiveSupport::SecurityUtils.secure_compare(request.headers['X-Jabvox-Internal-Token'].to_s, expected)
  rescue ArgumentError
    false
  end
end
