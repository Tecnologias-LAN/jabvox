# frozen_string_literal: true

# Orquesta una operación de la API Provisioner ya autenticada:
#   1. La operación debe existir en la whitelist (OperationRegistry) — si no, denegada.
#   2. El token debe permitir (recurso, acción) — consulta FRESCA, sin caché.
#   3. Despacha al handler interno correspondiente.
#   4. Audita SIEMPRE el resultado (ok/denied/error), con params saneados.
# Devuelve un Result con :ok/:data o :error(code, message, status).
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Provisioner
    class Executor
      Result = Struct.new(:ok, :data, :code, :message, :status, keyword_init: true) do
        def ok? = ok
      end

      def initialize(token:, ip:)
        @token = token
        @ip = ip
      end

      def call(operation:, params:) # rubocop:disable Metrics/AbcSize
        meta = OperationRegistry.find(operation)
        return denied(operation, nil, nil, 'unknown_operation', 'Operación desconocida', 404) if meta.nil?

        resource = meta[:resource]
        action = meta[:action]

        # Autorización FRESCA por operación (nunca caché). Si el permiso se quitó desde el
        # Super Admin, esta consulta ya lo refleja.
        unless JabvoxProvisionerApiToken.find_by(id: @token.id)&.allows?(resource, action)
          return denied(operation, resource, action, 'permission_denied', 'Permiso no habilitado para esta operación', 403)
        end

        data = dispatch(meta[:handler], params)
        audit(operation, resource, action, 'ok', nil, params, 200)
        Result.new(ok: true, data: data, status: 200)
      rescue Jabvox::Provisioner::Handlers::OperationError => e
        denied(operation, meta&.dig(:resource), meta&.dig(:action), 'operation_error', e.message, 422)
      rescue ActiveRecord::RecordInvalid => e
        denied(operation, meta&.dig(:resource), meta&.dig(:action), 'validation_error', e.record.errors.full_messages.join('; '), 422)
      rescue StandardError => e
        Rails.logger.error("[ProvisionerExecutor] #{operation} #{e.class}")
        denied(operation, meta&.dig(:resource), meta&.dig(:action), 'internal_error', 'No se pudo completar la operación', 500)
      end

      private

      # Módulos de handlers, en orden de búsqueda: se usa el primero que responda al método.
      HANDLER_MODULES = [
        Jabvox::Provisioner::Handlers,
        Jabvox::Provisioner::HandlersAdmin,
        Jabvox::Provisioner::HandlersPlatform
      ].freeze

      # Despacha al handler en el módulo que lo implemente.
      def dispatch(handler, params)
        p = params.is_a?(Hash) ? params.stringify_keys : {}
        mod = HANDLER_MODULES.find { |m| m.respond_to?(handler) }
        raise Jabvox::Provisioner::Handlers::OperationError, 'handler no implementado' if mod.nil?

        mod.public_send(handler, p)
      end

      def denied(operation, resource, action, code, message, status) # rubocop:disable Metrics/ParameterLists
        audit(operation, resource, action, status == 500 ? 'error' : 'denied', code, {}, status)
        Result.new(ok: false, code: code, message: message, status: status)
      end

      def audit(operation, resource, action, outcome, reason, params, status) # rubocop:disable Metrics/ParameterLists
        JabvoxProvisionerAuditLog.record!(
          token_id: @token.id, resource: resource, action: action, outcome: outcome,
          reason: reason || operation, ip: @ip,
          account_id: extract_account_id(params), params: params, status: status
        )
      end

      def extract_account_id(params)
        return nil unless params.is_a?(Hash)

        (params['account_id'] || params[:account_id] || params['id'] || params[:id]).presence&.to_i
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
