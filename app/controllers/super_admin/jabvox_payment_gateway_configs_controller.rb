# frozen_string_literal: true

# Panel Super Admin: selección/edición de la pasarela de pago activa y sus SECRETOS
# (api_key, secret_key), que se guardan cifrados en reposo. El modelo garantiza que solo
# una quede activa. Cambiar el token/secretos/proveedor aquí queda disponible de inmediato
# para el cobro, sin redeploy ni tocar el .env.
#
# Seguridad del formulario: los secretos NUNCA se precargan en el form (se ven vacíos). Si
# el super admin deja un campo de secreto vacío al guardar, se CONSERVA el valor actual;
# solo se reemplaza cuando escribe uno nuevo.
class SuperAdmin::JabvoxPaymentGatewayConfigsController < SuperAdmin::ApplicationController
  # Campos de secreto: vacío => no cambiar (se quita del payload para no pisar con "").
  SECRET_FIELDS = %i[api_key secret_key].freeze

  def resource_params
    permitted = params.require(:jabvox_payment_gateway_config).permit(
      :provider, :active, :sandbox, :public_token, :checkout_base_url, :api_key, :secret_key
    )
    SECRET_FIELDS.each { |f| permitted.delete(f) if permitted[f].blank? }
    permitted
  end
end
