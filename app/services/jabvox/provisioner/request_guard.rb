# frozen_string_literal: true

# Guardián de CADA petición a la API Provisioner. Revalida TODO desde cero, sin caché de
# autorización, en este orden (falla rápido y barato antes de tocar lógica):
#   1. Longitud del token (anti-DoS) y token activo (hash + comparación en tiempo constante).
#   2. IP en la allowlist del token (fresca desde BD).
#   3. Firma HMAC + timestamp dentro de ventana + nonce no reusado (anti-replay).
#   4. Sesión/cliente único (una sola conexión autorizada; IP fijada).
# La comprobación de PERMISO por operación se hace después, por operación (en el controlador),
# también fresca. Devuelve un Result con :ok o :error(code, status).
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Provisioner
    class RequestGuard
      MAX_TOKEN_LENGTH = 256
      SIGNATURE_WINDOW = 300 # segundos

      Result = Struct.new(:ok, :token, :session, :body, :code, :status, keyword_init: true) do
        def ok? = ok
      end

      # @param request [ActionDispatch::Request]
      def initialize(request)
        @request = request
      end

      def authenticate
        token = authenticate_token
        return err('invalid_token', 401) if token.nil?

        # Doble control de IP: la allowlist debe cubrir la IP calculada por Rails
        # (remote_ip, que descarta proxies confiables) Y la IP de conexión directa
        # (REMOTE_ADDR, no falsificable por el cliente vía X-Forwarded-For). Con un proxy
        # local (loopback), la directa es 127.0.0.1: en ese caso se exige que la allowlist
        # incluya el loopback O que remote_ip case — configurable con PROVISIONER_TRUST_XFF.
        return err('ip_not_allowed', 403) unless ip_permitted?(token)

        sig = verify_signature(token)
        return err(sig, 401) unless sig == :ok

        session = ensure_single_connection(token)
        return err('connection_conflict', 403) if session.nil?

        token.touch_used!
        # Se ejecuta EXACTAMENTE el cuerpo que se firmó (parseado una sola vez), no los params
        # que Rails reconstruye por separado. Así lo firmado == lo ejecutado.
        Result.new(ok: true, token: token, session: session, body: parsed_signed_body)
      end

      # IP real del cliente (respeta el proxy de confianza de Rails: remote_ip).
      def client_ip
        @request.remote_ip.to_s
      end

      # IP de la conexión TCP directa (no derivada de X-Forwarded-For): el cliente NO puede
      # falsearla. Detrás de un proxy local será el loopback.
      def direct_ip
        (@request.env['REMOTE_ADDR'] || @request.ip).to_s
      end

      # ¿La IP está permitida? Por defecto (estricto) exige que la conexión directa esté en la
      # allowlist — inmune a spoofing de X-Forwarded-For. Si la conexión directa es un
      # loopback/privado (proxy local de confianza), se acepta que remote_ip case la allowlist.
      # PROVISIONER_TRUST_XFF=true relaja a solo remote_ip (usar solo si el edge sanea XFF).
      def ip_permitted?(token)
        return true if token.ip_allowed?(direct_ip)
        return token.ip_allowed?(client_ip) if trust_forwarded_ip? || loopback_or_private?(direct_ip)

        false
      end

      def trust_forwarded_ip?
        ActiveModel::Type::Boolean.new.cast(ENV.fetch('PROVISIONER_TRUST_XFF', nil))
      end

      def loopback_or_private?(ip)
        addr = IPAddr.new(ip)
        addr.loopback? || addr.private?
      rescue IPAddr::Error
        false
      end

      private

      def err(code, status)
        Result.new(ok: false, code: code, status: status)
      end

      # Bearer o X-Provisioner-Token. Guard de longitud ANTES de tocar BD.
      def authenticate_token
        raw = bearer_token
        return nil if raw.blank? || raw.length > MAX_TOKEN_LENGTH

        JabvoxProvisionerApiToken.authenticate(raw)
      end

      def bearer_token
        header = @request.headers['Authorization'].to_s
        return Regexp.last_match(1) if header =~ /\ABearer\s+(.+)\z/i

        @request.headers['X-Provisioner-Token'].to_s
      end

      # Firma HMAC-SHA256 sobre "{timestamp}.{nonce}.{cuerpo_crudo}" con el SECRETO DE FIRMA
      # del token (independiente del Bearer, cifrado en reposo) como clave. Así, capturar el
      # header Bearer no basta para forjar firmas. Exige timestamp fresco (±ventana) y nonce no
      # reusado. Devuelve :ok o el código de error.
      def verify_signature(token) # rubocop:disable Metrics/CyclomaticComplexity
        secret = token.signing_secret_jabvox.to_s
        return :no_signing_secret if secret.blank?

        ts = @request.headers['X-Provisioner-Timestamp'].to_s
        nonce = @request.headers['X-Provisioner-Nonce'].to_s
        signature = @request.headers['X-Provisioner-Signature'].to_s
        return :missing_signature if ts.blank? || nonce.blank? || signature.blank?

        return :stale_timestamp unless fresh_timestamp?(ts)

        expected = compute_signature(secret, ts, nonce)
        return :bad_signature unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)

        # Registra el nonce SOLO tras validar la firma (evita llenar la tabla con basura).
        return :replay unless JabvoxProvisionerNonce.register(nonce)

        :ok
      end

      def fresh_timestamp?(ts) # rubocop:disable Naming/MethodParameterName
        t = Integer(ts, exception: false)
        return false if t.nil?

        (Time.current.to_i - t).abs <= SIGNATURE_WINDOW
      end

      def compute_signature(secret, ts, nonce) # rubocop:disable Naming/MethodParameterName
        OpenSSL::HMAC.hexdigest('sha256', secret, "#{ts}.#{nonce}.#{raw_body}")
      end

      def raw_body
        @raw_body ||= begin
          body = @request.raw_post.to_s
          @request.body.rewind if @request.body.respond_to?(:rewind)
          body
        end
      end

      # Parsea el MISMO cuerpo crudo que se firmó (JSON). Si no es JSON válido, devuelve {}.
      # Se ejecuta esto, no los params reconstruidos por Rails, para evitar cualquier desfase
      # entre lo firmado y lo ejecutado.
      def parsed_signed_body
        JSON.parse(raw_body)
      rescue JSON::ParserError
        {}
      end

      # Una sola conexión autorizada. El client_id lo envía Hermes; la IP se fija en el 1er
      # handshake. Otra identidad/IP con sesión activa → nil (403).
      def ensure_single_connection(token)
        client_id = @request.headers['X-Provisioner-Client'].to_s
        return nil if client_id.blank?

        JabvoxProvisionerSession.ensure_single!(
          token: token, client_id: client_id, ip: client_ip,
          fingerprint: @request.headers['X-Provisioner-Fingerprint'].to_s.presence
        )
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
