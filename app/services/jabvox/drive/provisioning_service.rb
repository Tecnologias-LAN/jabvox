# frozen_string_literal: true

# Aprovisiona el AISLAMIENTO DURO por cuenta en MinIO: crea (idempotente) un usuario
# de servicio por cuenta y una policy IAM que SOLO permite operar sobre su prefijo
# `acct-<id>/` en ambos buckets. Así, aunque la app tuviera un bug, MinIO rechaza con
# 403 cualquier acceso al prefijo de otra cuenta (defensa en profundidad).
#
# Usa la identidad de APROVISIONAMIENTO (separada de la de ejecución y del root):
#   JABVOX_DRIVE_PROVISIONER_ACCESS_KEY / _SECRET_KEY
#
# Implementación: se apoya en el binario `mc` (MinIO Client) apuntando al alias de
# aprovisionamiento. En desarrollo `mc` vive dentro del contenedor; en producción es
# el `mc` del host. El comando se resuelve por ENV JABVOX_DRIVE_MC_CMD (default: "mc").
# Es idempotente: crear un usuario/policy que ya existe no es un error.
#
# Nota: el aislamiento a nivel de APP ya está garantizado por StorageService (prefijo
# forzado + assert_owned!). Este servicio añade la barrera a nivel de MinIO. Si no se
# aprovisiona (p. ej. entornos sin acceso admin), el Drive sigue funcionando con la
# credencial de ejecución; por eso los errores aquí se registran y NO rompen el alta.
module Jabvox
  module Drive
    class ProvisioningService
      attr_reader :account

      def initialize(account)
        raise ArgumentError, 'account requerido' if account.nil?

        @account = account
      end

      def self.enabled?
        ActiveModel::Type::Boolean.new.cast(ENV.fetch('JABVOX_DRIVE_PROVISION_PER_ACCOUNT', 'false'))
      end

      # Crea/actualiza usuario + policy de la cuenta. Idempotente. Devuelve true/false.
      # La policy se pasa por STDIN (/dev/stdin) para funcionar tanto si `mc` corre en
      # el host como dentro del contenedor (en dev vía `docker exec`).
      def provision!
        return false unless self.class.enabled?

        policy_ok = create_policy!
        user_ok = run_mc('admin', 'user', 'add', alias_name, svc_user, svc_secret)
        attach_ok = run_mc('admin', 'policy', 'attach', alias_name, policy_name, '--user', svc_user)
        ok = policy_ok && user_ok && attach_ok
        unless ok
          Rails.logger.error("[jabvox-drive] provision! incompleto account_id=#{account.id} " \
                             "policy=#{policy_ok} user=#{user_ok} attach=#{attach_ok}")
        end
        ok
      rescue StandardError => e
        # No romper el alta de la cuenta por un fallo de aprovisionamiento de MinIO.
        Rails.logger.error("[jabvox-drive] provision! falló account_id=#{account.id}: #{e.class}")
        false
      end

      # Nombres estables y sin información sensible.
      def svc_user
        "svc-acct-#{account.id}"
      end

      def policy_name
        "jabvox-drive-acct-#{account.id}"
      end

      def account_prefix
        "acct-#{account.id}/"
      end

      private

      # Secreto de la credencial de cuenta: derivado de forma determinista de un
      # secreto base (para poder re-aprovisionar sin almacenarlo). En producción se
      # recomienda rotarlo y guardarlo cifrado si se usa para acceso directo; aquí la
      # app NO usa esta credencial para I/O (usa la de ejecución), es solo la que
      # ataría un acceso directo por-cuenta si se habilita STS/directo en el futuro.
      def svc_secret
        base = ENV.fetch('JABVOX_DRIVE_ACCOUNT_SECRET_BASE', nil)
        raise 'JABVOX_DRIVE_ACCOUNT_SECRET_BASE no configurado' if base.blank?

        Digest::SHA256.hexdigest("#{base}:#{account.id}")
      end

      def primary_bucket
        StorageService.primary_bucket
      end

      def overflow_bucket
        StorageService.overflow_bucket
      end

      def policy_json
        {
          'Version' => '2012-10-17',
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => %w[s3:GetObject s3:PutObject s3:DeleteObject],
              'Resource' => [
                "arn:aws:s3:::#{primary_bucket}/#{account_prefix}*",
                "arn:aws:s3:::#{overflow_bucket}/#{account_prefix}*"
              ]
            },
            {
              'Effect' => 'Allow',
              'Action' => %w[s3:ListBucket],
              'Resource' => ["arn:aws:s3:::#{primary_bucket}", "arn:aws:s3:::#{overflow_bucket}"],
              'Condition' => { 'StringLike' => { 's3:prefix' => ["#{account_prefix}*"] } }
            }
          ]
        }
      end

      # Crea la policy pasando el JSON por STDIN (/dev/stdin). Idempotente.
      def create_policy!
        run_mc('admin', 'policy', 'create', alias_name, policy_name, '/dev/stdin',
               stdin: JSON.generate(policy_json))
      end

      def alias_name
        ENV.fetch('JABVOX_DRIVE_MC_ALIAS', 'local')
      end

      # Ejecuta `mc` de forma segura (sin shell, args como array). Devuelve true si
      # el comando tuvo éxito. No loguea secretos. Acepta `stdin:` para pasar la policy.
      def run_mc(*args, stdin: nil)
        cmd = Array(mc_cmd) + args
        out, status = if stdin
                        Open3.capture2e(*cmd, stdin_data: stdin)
                      else
                        Open3.capture2e(*cmd)
                      end
        ok = status.success?
        # 'already exists' no es error real (idempotencia).
        ok ||= out.to_s.match?(/already exists|already has/i)
        Rails.logger.warn("[jabvox-drive] mc #{args.first(3).join(' ')} rc=#{status.exitstatus}") unless ok
        ok
      end

      def mc_cmd
        ENV.fetch('JABVOX_DRIVE_MC_CMD', 'mc').split
      end
    end
  end
end
