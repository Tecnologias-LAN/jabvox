# frozen_string_literal: true

require 'aws-sdk-s3'

# Servicio centralizado de almacenamiento del módulo jabvox-drive.
#
# ÚNICO punto por el que el Drive habla con MinIO/S3. Garantiza el aislamiento
# por empresa: TODA operación se prefija con `acct-<id>/` derivado de la cuenta
# que recibe el servicio (resuelta aguas arriba desde `Current.account`), nunca
# de un dato suministrado por el cliente.
#
# Reglas de seguridad (ver CLAUDE.md y skill jabvox-security):
#   - La cuenta se pasa al construir el servicio; no se acepta account_id suelto.
#   - object_key(...) rechaza cualquier intento de path traversal o de salir del
#     prefijo de la cuenta (defensa en profundidad; MinIO además lo bloquea por
#     policy IAM de prefijo).
#   - Nunca se devuelven credenciales ni URLs internas al navegador: las descargas
#     pasan por Jabvox (presigned de vida corta o streaming desde el controller).
#
# Buckets:
#   primary  -> ENV['JABVOX_DRIVE_BUCKET']           (archivos autorizados)
#   overflow -> ENV['JABVOX_DRIVE_OVERFLOW_BUCKET']  (cuarentena por cuota)
module Jabvox
  module Drive
    class StorageService
      class InvalidKeyError < StandardError; end
      class StorageUnavailableError < StandardError; end
      # El objeto no existe en MinIO (p. ej. la fila del Drive quedó huérfana). Es
      # distinto de "MinIO caído": el controller debe responder 404, no 503.
      class ObjectNotFoundError < StandardError; end

      PRIMARY = 'primary'
      OVERFLOW = 'overflow'

      attr_reader :account

      def initialize(account)
        raise ArgumentError, 'account requerido' if account.nil?

        @account = account
      end

      # Prefijo inmutable de la cuenta. Estable, sin información sensible.
      def account_prefix
        "acct-#{account.id}/"
      end

      # Construye la object_key completa y SEGURA a partir de una ruta relativa.
      # Rechaza rutas absolutas, "..", bytes nulos y cualquier intento de evadir
      # el prefijo de la cuenta.
      def object_key(relative_path)
        rel = relative_path.to_s
        raise InvalidKeyError, 'ruta vacía' if rel.blank?
        raise InvalidKeyError, 'ruta inválida' if rel.include?("\u0000")
        raise InvalidKeyError, 'ruta inválida' if rel.start_with?('/')

        normalized = normalize_segments(rel)
        "#{account_prefix}#{normalized}"
      end

      # Verifica que una object_key ya existente pertenece a ESTA cuenta.
      # Se usa antes de get/delete/presign sobre claves tomadas de la BD, como
      # última barrera frente a filas corruptas o IDs manipulados.
      def owns_key?(key)
        key.to_s.start_with?(account_prefix)
      end

      def assert_owned!(key)
        raise InvalidKeyError, 'objeto fuera del ámbito de la cuenta' unless owns_key?(key)
      end

      # Sube un objeto. Devuelve { key:, bucket:, byte_size:, sha256: }.
      def put(relative_path, io, content_type: nil, bucket: PRIMARY)
        key = object_key(relative_path)
        data = io.respond_to?(:read) ? io.read : io.to_s
        sha = Digest::SHA256.hexdigest(data)
        client.put_object({
          bucket: bucket_name(bucket),
          key: key,
          body: data,
          content_type: content_type
        }.merge(sse_options))
        { key: key, bucket: bucket, byte_size: data.bytesize, sha256: sha }
      rescue Seahorse::Client::NetworkingError, Aws::S3::Errors::ServiceError => e
        raise StorageUnavailableError, e.message
      end

      # Descarga el cuerpo del objeto (para streaming desde el controller).
      def get(key, bucket: PRIMARY)
        assert_owned!(key)
        client.get_object(bucket: bucket_name(bucket), key: key).body.read
      rescue Aws::S3::Errors::NoSuchKey
        nil
      rescue Seahorse::Client::NetworkingError, Aws::S3::Errors::ServiceError => e
        raise StorageUnavailableError, e.message
      end

      # Stream del objeto en bloques, sin cargarlo entero en memoria.
      def stream(key, bucket: PRIMARY, &)
        assert_owned!(key)
        client.get_object(bucket: bucket_name(bucket), key: key, &)
      rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound => e
        # Objeto inexistente (fila huérfana): NO es MinIO caído. 404, no 503.
        raise ObjectNotFoundError, e.message
      rescue Seahorse::Client::NetworkingError, Aws::S3::Errors::ServiceError => e
        raise StorageUnavailableError, e.message
      end

      # URL firmada de vida CORTA. Uso interno/servidor; nunca se expone cruda al
      # navegador salvo como redirección breve controlada por el controller.
      def presigned_get(key, bucket: PRIMARY, expires_in: 60, disposition: 'inline', filename: nil)
        assert_owned!(key)
        params = { bucket: bucket_name(bucket), key: key }
        params[:response_content_disposition] = "#{disposition}; filename=\"#{sanitize_filename(filename)}\"" if filename.present?
        presigner.presigned_url(:get_object, expires_in: expires_in, **params)
      end

      def delete(key, bucket: PRIMARY)
        assert_owned!(key)
        client.delete_object(bucket: bucket_name(bucket), key: key)
        true
      rescue Seahorse::Client::NetworkingError, Aws::S3::Errors::ServiceError => e
        raise StorageUnavailableError, e.message
      end

      # Comprueba existencia y devuelve el tamaño, o nil si no existe.
      def head(key, bucket: PRIMARY)
        assert_owned!(key)
        resp = client.head_object(bucket: bucket_name(bucket), key: key)
        { byte_size: resp.content_length, content_type: resp.content_type }
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
        nil
      rescue Seahorse::Client::NetworkingError, Aws::S3::Errors::ServiceError => e
        raise StorageUnavailableError, e.message
      end

      # Copia un objeto (p. ej. overflow -> primary al regularizar cuota).
      # Ambas claves se validan contra el prefijo de la cuenta.
      def copy(src_key, dst_key, src_bucket:, dst_bucket:)
        assert_owned!(src_key)
        assert_owned!(dst_key)
        client.copy_object({
          bucket: bucket_name(dst_bucket),
          copy_source: "#{bucket_name(src_bucket)}/#{src_key}",
          key: dst_key
        }.merge(sse_options))
        true
      rescue Seahorse::Client::NetworkingError, Aws::S3::Errors::ServiceError => e
        raise StorageUnavailableError, e.message
      end

      # Lista objetos del prefijo de la cuenta (nunca de otra).
      def list(sub_prefix = '', bucket: PRIMARY, max_keys: 1000)
        prefix = sub_prefix.present? ? object_key(sub_prefix) : account_prefix
        client.list_objects_v2(bucket: bucket_name(bucket), prefix: prefix, max_keys: max_keys)
              .contents.map { |o| { key: o.key, size: o.size, last_modified: o.last_modified } }
      rescue Seahorse::Client::NetworkingError, Aws::S3::Errors::ServiceError => e
        raise StorageUnavailableError, e.message
      end

      # ¿MinIO responde? Para health checks y para decidir encolar en vez de fallar.
      def available?
        client.head_bucket(bucket: bucket_name(PRIMARY))
        true
      rescue StandardError
        false
      end

      class << self
        def configured?
          endpoint.present? && access_key.present? && secret_key.present? &&
            primary_bucket.present? && overflow_bucket.present?
        end

        def endpoint
          ENV.fetch('JABVOX_DRIVE_ENDPOINT', ENV.fetch('STORAGE_ENDPOINT', '')).presence
        end

        def region
          ENV.fetch('JABVOX_DRIVE_REGION', ENV.fetch('STORAGE_REGION', 'us-east-1'))
        end

        def access_key
          ENV.fetch('JABVOX_DRIVE_ACCESS_KEY_ID', ENV.fetch('STORAGE_ACCESS_KEY_ID', '')).presence
        end

        def secret_key
          ENV.fetch('JABVOX_DRIVE_SECRET_ACCESS_KEY', ENV.fetch('STORAGE_SECRET_ACCESS_KEY', '')).presence
        end

        def primary_bucket
          ENV.fetch('JABVOX_DRIVE_BUCKET', 'jabvox-drive').presence
        end

        def overflow_bucket
          ENV.fetch('JABVOX_DRIVE_OVERFLOW_BUCKET', 'jabvox-drive-overflow').presence
        end
      end

      private

      def bucket_name(bucket)
        case bucket
        when PRIMARY then self.class.primary_bucket
        when OVERFLOW then self.class.overflow_bucket
        else raise ArgumentError, "bucket inválido: #{bucket}"
        end
      end

      # Normaliza segmentos: colapsa //, resuelve . , y rechaza .. para que sea
      # imposible salir del prefijo de la cuenta.
      def normalize_segments(rel)
        segments = rel.split('/').reject { |s| s.blank? || s == '.' }
        raise InvalidKeyError, 'ruta inválida' if segments.include?('..')

        segments.join('/')
      end

      # Cifrado en reposo. En producción con KMS: JABVOX_DRIVE_SSE=aws:kms +
      # JABVOX_DRIVE_SSE_KMS_KEY_ID. Con SSE-S3 (MinIO con KMS habilitado):
      # JABVOX_DRIVE_SSE=AES256. En dev sin KMS se deja vacío (sin SSE a nivel
      # de petición; el cifrado en reposo lo da el almacenamiento del servidor).
      def sse_options
        mode = ENV.fetch('JABVOX_DRIVE_SSE', '').presence
        return {} if mode.blank?

        opts = { server_side_encryption: mode }
        if mode == 'aws:kms'
          key_id = ENV.fetch('JABVOX_DRIVE_SSE_KMS_KEY_ID', '').presence
          opts[:sse_kms_key_id] = key_id if key_id
        end
        opts
      end

      def sanitize_filename(name)
        File.basename(name.to_s).tr('"', '').gsub(/[\u0000-\u001f]/, '')
      end

      def client
        @client ||= build_client
      end

      def presigner
        @presigner ||= Aws::S3::Presigner.new(client: client)
      end

      def build_client
        raise StorageUnavailableError, 'jabvox-drive no configurado' unless self.class.configured?

        options = {
          region: self.class.region,
          access_key_id: self.class.access_key,
          secret_access_key: self.class.secret_key,
          endpoint: self.class.endpoint,
          force_path_style: true,
          # TIMEOUTS y reintentos acotados: evitan que una request lenta a MinIO (o al
          # prefijo de una cuenta) cuelgue un thread del worker indefinidamente y
          # degrade a TODAS las cuentas (aislamiento de fallos / blast radius).
          http_open_timeout: ENV.fetch('JABVOX_DRIVE_OPEN_TIMEOUT', '5').to_i,
          http_read_timeout: ENV.fetch('JABVOX_DRIVE_READ_TIMEOUT', '30').to_i,
          retry_limit: ENV.fetch('JABVOX_DRIVE_RETRY_LIMIT', '2').to_i
        }
        # En dev/MinIO sin TLS verificado; en prod con TLS real se omite.
        options[:ssl_verify_peer] = false if ActiveModel::Type::Boolean.new.cast(ENV.fetch('JABVOX_DRIVE_INSECURE_TLS', 'false'))
        Aws::S3::Client.new(**options)
      end
    end
  end
end
