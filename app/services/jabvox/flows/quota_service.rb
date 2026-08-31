# frozen_string_literal: true

# Tope de flujos por cuenta. El límite sale de dos sitios y manda el MENOR de los
# definidos: el override del super admin (account_automation_configs.max_flows) y
# lo incluido en el plan (effective_limit_for(:advanced_flows)).
class Jabvox::Flows::QuotaService
  # Espacio de nombres del advisory lock; el segundo argumento es el account_id.
  LOCK_NAMESPACE = 8_421_701

  class QuotaExceeded < StandardError; end

  def initialize(account)
    @account = account
  end

  # nil = ilimitado. Un 0 en el plan significa "no definido", no "cero flujos":
  # es el valor que devuelve effective_limit_for cuando no hay nada configurado.
  def limit
    candidates = [@account.account_automation_config&.max_flows,
                  @account.effective_limit_for(:advanced_flows).to_i].map(&:to_i).select(&:positive?)
    candidates.min
  end

  def used
    @account.jabvox_flows.count
  end

  def unlimited?
    limit.nil?
  end

  def remaining
    return nil if unlimited?

    [limit - used, 0].max
  end

  def exceeded?
    !unlimited? && used >= limit
  end

  def as_json(*)
    { 'used' => used, 'limit' => limit, 'remaining' => remaining, 'unlimited' => unlimited? }
  end

  def error_message
    "Has alcanzado el límite de flujos de tu plan: #{used} de #{limit}. " \
      'Borra un flujo que no uses o solicita ampliar el tope.'
  end

  # Reserva un hueco y crea el flujo dentro de la MISMA transacción. El advisory
  # lock por cuenta serializa la ventana contar+insertar, así que N peticiones
  # concurrentes nunca pueden pasar del tope. Falla cerrado: sin hueco, no crea.
  def create!(&)
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute(
        "SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{@account.id.to_i})"
      )
      raise QuotaExceeded, error_message if exceeded?

      yield
    end
  end
end
