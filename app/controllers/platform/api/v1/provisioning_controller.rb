# Aprovisionamiento de cuentas en un solo paso, para automatizaciones externas (n8n
# al recibir un pago). Autenticado con el api_access_token de un PlatformApp (igual
# que el resto de la Platform API). Crea cuenta + admin, activa módulos y fija límites
# de forma atómica vía Jabvox::AccountProvisioningService.
#
# POST /platform/api/v1/provisioning
#   {
#     "email": "cliente@empresa.com",
#     "name": "Empresa X",
#     "admin_name": "Juan",
#     "password": "opcional",
#     "locale": "es",
#     "modules": ["tickets", "kanban", "analytics", "advanced_automations"],
#     "limits": { "inboxes": 5, "agents": 10, "automation_rules": 20,
#                 "advanced_flows": 5, "analytics_dashboards": 3,
#                 "ai_documents": 100, "forms": 10 },
#     "idempotency_key": "cs_test_...."   # id del pago; reintento seguro (o header Idempotency-Key)
#   }
class Platform::Api::V1::ProvisioningController < PlatformController
  def create
    result = Jabvox::AccountProvisioningService.new(provisioning_params).call

    # La cuenta queda ligada a este PlatformApp (mismo patrón que accounts#create),
    # para que luego pueda gestionarla vía la Platform API.
    @platform_app.platform_app_permissibles.find_or_create_by(permissible: result[:account])

    render json: serialize(result), status: :created
  rescue Jabvox::AccountProvisioningService::ProvisioningError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def provisioning_params
    permitted = params.permit(:email, :name, :admin_name, :password, :locale, :idempotency_key,
                              modules: [], features: [], limits: {}).to_h.symbolize_keys
    # base_url para armar el link de set-password: el que envíe la web o el host actual.
    permitted[:base_url] = params[:base_url].presence || request.base_url
    # Idempotencia: acepta también el header estándar Idempotency-Key (reintentos de n8n).
    permitted[:idempotency_key] = permitted[:idempotency_key].presence ||
                                  request.headers['Idempotency-Key'].presence
    permitted
  end

  def serialize(result)
    {
      account_id: result[:account].id,
      account_name: result[:account].name,
      admin_user_id: result[:user].id,
      admin_email: result[:user].email,
      created_user: result[:created_user],
      modules_enabled: result[:modules],
      features_enabled: result[:features],
      limits: result[:limits],
      # Enlace ÚNICO y temporal para que el admin cree su contraseña (no va password en claro).
      set_password_url: result[:set_password_url],
      # true si fue un reintento (la cuenta ya existía por idempotency_key); n8n puede
      # saltarse el envío de correo en ese caso.
      replayed: result[:replayed] || false
    }
  end
end
