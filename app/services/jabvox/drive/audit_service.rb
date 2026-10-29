# frozen_string_literal: true

# Escribe la bitácora de auditoría del Drive. Punto ÚNICO de registro: cada operación
# (subir, descargar, renombrar, mover, eliminar, crear/mover carpeta, overflow,
# regularización) pasa por aquí. Nunca registra contenido de archivos, tokens ni URLs
# firmadas — solo metadatos seguros (nombres, ids, bytes, estado).
#
# El registro NUNCA debe romper la operación de negocio: si falla, se loguea y sigue.
module Jabvox
  module Drive
    class AuditService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Registra una acción. `actor` es el User que la hizo (o nil = sistema/job).
      # `auditable` es el JabvoxDriveFile/Folder afectado (opcional).
      # `request` (opcional) aporta ip/user_agent sin exponer nada sensible.
      def log(action:, actor: nil, auditable: nil, result: 'success', metadata: {}, request: nil)
        JabvoxDriveAuditLog.create!(
          account_id: account.id,
          user_id: actor&.id,
          action: action.to_s,
          result: result.to_s,
          auditable_type: auditable&.class&.name,
          auditable_id: auditable&.id,
          ip_address: request&.remote_ip,
          user_agent: request&.user_agent&.to_s&.first(500),
          metadata: sanitize(metadata)
        )
      rescue StandardError => e
        # La auditoría no debe tumbar la operación; se registra el fallo y se continúa.
        Rails.logger.error("[jabvox-drive] audit log falló account_id=#{account&.id} action=#{action}: #{e.class}")
        nil
      end

      private

      # Quita cualquier clave potencialmente sensible y recorta valores largos.
      def sanitize(metadata)
        forbidden = /pass|secret|token|key|credential|url|body|content|data/i
        (metadata || {}).each_with_object({}) do |(k, v), acc|
          next if k.to_s.match?(forbidden)

          acc[k] = v.is_a?(String) ? v.first(500) : v
        end
      end
    end
  end
end
