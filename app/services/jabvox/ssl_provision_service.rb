require 'acme-client'
require 'fileutils'

module Jabvox
  class SslProvisionService
    ACME_DIRECTORY = ENV.fetch(
      'JABVOX_ACME_DIRECTORY',
      'https://acme-v02.api.letsencrypt.org/directory'
    ).freeze
    CERTS_DIR    = ENV.fetch('JABVOX_SSL_CERTS_DIR', Rails.root.join('storage', 'jabvox_ssl').to_s).freeze
    NGINX_SITES  = ENV.fetch('JABVOX_NGINX_SITES_DIR', '').freeze
    NGINX_RELOAD = ENV.fetch('JABVOX_NGINX_RELOAD_CMD', '').freeze
    UPSTREAM     = ENV.fetch('JABVOX_UPSTREAM', 'http://localhost:3000').freeze

    CHALLENGE_TTL       = 30.minutes
    VALIDATION_TIMEOUT  = 4.minutes
    ISSUANCE_TIMEOUT    = 3.minutes
    POLL_INTERVAL       = 5

    def initialize(config)
      @config = config
      @domain = extract_domain(config.base_url_jabvox)
    end

    def call
      validate!
      client = build_client
      order  = client.new_order(identifiers: [@domain])
      validate_challenge(order)
      issue_certificate(order)
      persist_files
      write_nginx_config if NGINX_SITES.present?
      finalize_config
    rescue StandardError => e
      Rails.logger.error("Jabvox SSL provision failed for #{@domain}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      @config.update_columns(ssl_status: 'failed', ssl_error: e.message.truncate(500))
      raise
    ensure
      cleanup_challenge
    end

    private

    def extract_domain(raw)
      return raw.strip if raw.blank?

      URI.parse(raw.strip).hostname.presence || raw.strip
    rescue URI::InvalidURIError
      raw.to_s.sub(%r{^https?://}, '').split('/').first.to_s.strip
    end

    VALID_DOMAIN_RE = /\A[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)+\z/i

    def validate!
      raise 'No se ha configurado un dominio personalizado' if @domain.blank?
      raise 'Dominio inválido' unless @domain.match?(VALID_DOMAIN_RE)
      raise 'El dominio no puede ser una dirección IP' if @domain.match?(/\A\d{1,3}(\.\d{1,3}){3}\z/)
    end

    def build_client
      key_pem = @config.acme_account_key
      if key_pem.blank?
        account_key = OpenSSL::PKey::RSA.new(4096)
        @config.update_column(:acme_account_key, account_key.to_pem)
      else
        account_key = OpenSSL::PKey::RSA.new(key_pem)
      end

      client = Acme::Client.new(private_key: account_key, directory: ACME_DIRECTORY)
      acme_email = ENV.fetch('JABVOX_ACME_EMAIL', "ssl@#{@domain}")
      client.new_account(contact: "mailto:#{acme_email}", terms_of_service_agreed: true)
      client
    end

    def validate_challenge(order)
      authorization = order.authorizations.first
      @challenge    = authorization.http
      @token        = @challenge.token

      Rails.cache.write("jabvox_acme_#{@token}", @challenge.file_content, expires_in: CHALLENGE_TTL)
      @challenge.request_validation

      deadline = VALIDATION_TIMEOUT.from_now
      loop do
        sleep POLL_INTERVAL
        @challenge.reload
        case @challenge.status
        when 'valid'
          break
        when 'invalid'
          detail = @challenge.error&.dig('detail') || 'desconocido'
          raise "Validación del dominio fallida: #{detail}. Verifica que el CNAME apunte a este servidor y que el puerto 80 esté accesible."
        end
        raise 'Tiempo de espera agotado en validación del dominio (¿DNS propagado?)' if Time.current > deadline
      end
    end

    def issue_certificate(order)
      @cert_key = OpenSSL::PKey::RSA.new(4096)
      csr = Acme::Client::CertificateRequest.new(
        private_key: @cert_key,
        subject: { common_name: @domain },
        names: [@domain]
      )
      order.finalize(csr: csr)

      deadline = ISSUANCE_TIMEOUT.from_now
      loop do
        sleep 3
        order.reload
        break if order.status == 'valid'
        raise 'Tiempo de espera agotado al emitir el certificado' if Time.current > deadline
      end

      @cert_pem = order.certificate
    end

    def persist_files
      domain_dir = File.join(CERTS_DIR, @domain)
      FileUtils.mkdir_p(domain_dir, mode: 0o700)

      @cert_path = File.join(domain_dir, 'fullchain.pem')
      @key_path  = File.join(domain_dir, 'privkey.pem')

      File.open(@cert_path, File::CREAT | File::WRONLY | File::TRUNC, 0o644) { |f| f.write(@cert_pem) }
      File.open(@key_path,  File::CREAT | File::WRONLY | File::TRUNC, 0o600) { |f| f.write(@cert_key.to_pem) }
    end

    NGINX_TEMPLATE = <<~'NGINX'
      # Managed by Jabvox SSL – do not edit manually
      # Domain: %<domain>s – Issued: %<issued_at>s
      server {
        listen 80;
        server_name %<domain>s;

        location /.well-known/acme-challenge/ {
          proxy_pass         %<upstream>s;
          proxy_set_header   Host $host;
          proxy_set_header   X-Real-IP $remote_addr;
        }

        location / {
          return 301 https://$host$request_uri;
        }
      }

      server {
        listen 443 ssl;
        server_name %<domain>s;

        ssl_certificate      %<cert_path>s;
        ssl_certificate_key  %<key_path>s;
        ssl_protocols        TLSv1.2 TLSv1.3;
        ssl_ciphers          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_timeout  1d;
        ssl_session_cache    shared:SSL:10m;
        ssl_session_tickets  off;
        add_header Strict-Transport-Security "max-age=63072000" always;

        location / {
          proxy_pass         %<upstream>s;
          proxy_http_version 1.1;
          proxy_set_header   Upgrade $http_upgrade;
          proxy_set_header   Connection "upgrade";
          proxy_set_header   Host $host;
          proxy_set_header   X-Real-IP $remote_addr;
          proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header   X-Forwarded-Proto $scheme;
          proxy_cache_bypass $http_upgrade;
        }
      }
    NGINX

    def write_nginx_config
      content = format(
        NGINX_TEMPLATE,
        domain: @domain,
        issued_at: Time.current.utc.strftime('%Y-%m-%d'),
        cert_path: @cert_path,
        key_path: @key_path,
        upstream: UPSTREAM
      )
      conf_path = File.join(NGINX_SITES, "jabvox-ssl-#{@domain}.conf")
      File.write(conf_path, content)
      reload_nginx
    rescue StandardError => e
      Rails.logger.warn("Jabvox SSL: nginx config write failed (cert still saved): #{e.message}")
    end

    def reload_nginx
      return if NGINX_RELOAD.blank?

      output = `#{NGINX_RELOAD} 2>&1`
      raise "nginx reload falló: #{output.strip}" unless $CHILD_STATUS.success?
    end

    def finalize_config
      x509 = OpenSSL::X509::Certificate.new(@cert_pem)
      @config.update!(
        ssl_status: 'active',
        ssl_cert: @cert_pem,
        ssl_key: @cert_key.to_pem,
        ssl_expires_at: x509.not_after,
        ssl_error: nil,
        ssl_provisioned_at: Time.current
      )
    end

    def cleanup_challenge
      Rails.cache.delete("jabvox_acme_#{@token}") if @token
    end
  end
end
