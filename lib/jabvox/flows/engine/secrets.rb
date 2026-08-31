# frozen_string_literal: true

# Redacción de valores secretos antes de persistir la traza. Si un param
# interpoló `{{global.api_key}}`, el valor resuelto no debe quedar legible en el
# historial. Comparación por valor literal, así que cubre tanto el param crudo
# como una salida que devuelva el secreto reflejado.
module Jabvox::Flows::Engine::Secrets
  MASK = '••••'

  module_function

  def redact(value, secret_values)
    return value if secret_values.blank?

    case value
    when String then mask(value, secret_values)
    when Array then value.map { |v| redact(v, secret_values) }
    when Hash then value.transform_values { |v| redact(v, secret_values) }
    else value
    end
  end

  def mask(text, secret_values)
    secret_values.reduce(text) { |acc, secret| secret.present? ? acc.gsub(secret, MASK) : acc }
  end
end
