# frozen_string_literal: true

# Endpoints de la API Provisioner:
#   GET  /api/provisioner/catalog          → operaciones que el token TIENE habilitadas
#   POST /api/provisioner/execute          → { operation, params } ejecuta una operación
#
# La ejecución delega en Executor, que revalida el permiso FRESCO por operación y audita.
class Api::Provisioner::OperationsController < Api::Provisioner::BaseController
  # Solo las operaciones cuyo (recurso, acción) el token permite AHORA (consulta fresca).
  #
  # Cada operación viene con su manual de uso (qué hace, qué parámetros admite y qué
  # devuelve): con el recurso/acción a secas el Hermes podría autorizarse pero no sabría
  # cómo llamar nada, y acabaría adivinando nombres de parámetros.
  def catalog
    token = JabvoxProvisionerApiToken.find_by(id: guarded_token.id)
    allowed = Jabvox::Provisioner::OperationRegistry.catalog.select do |_op, meta|
      token&.allows?(meta[:resource], meta[:action])
    end
    render json: { operations: Jabvox::Provisioner::OperationDocs.catalog_with_docs(only: allowed.keys) }
  end

  def execute
    # Se usa el cuerpo FIRMADO (parseado una sola vez en el guard), no params de Rails, para
    # garantizar que lo ejecutado sea exactamente lo firmado.
    operation = signed_body['operation'].to_s
    op_params = signed_body['params']
    op_params = op_params.is_a?(Hash) ? op_params : {}

    result = Jabvox::Provisioner::Executor.new(token: guarded_token, ip: client_ip)
                                          .call(operation: operation, params: op_params)

    if result.ok?
      render json: { ok: true, data: result.data }, status: :ok
    else
      render json: { ok: false, error: result.code, message: result.message }, status: result.status
    end
  end
end
