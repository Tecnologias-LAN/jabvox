# frozen_string_literal: true

# Panel Super Admin: selección/edición de la pasarela de pago activa. El modelo garantiza
# que solo una quede activa (desactiva las demás al activar una). Cambiar el token o el
# proveedor aquí queda inmediatamente disponible para la web (que lo consulta a la app),
# sin redeploy.
class SuperAdmin::JabvoxPaymentGatewayConfigsController < SuperAdmin::ApplicationController
end
