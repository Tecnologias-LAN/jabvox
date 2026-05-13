require 'fileutils'

module Jabvox
  class SslRevokeService
    CERTS_DIR    = ENV.fetch('JABVOX_SSL_CERTS_DIR', Rails.root.join('storage', 'jabvox_ssl').to_s).freeze
    NGINX_SITES  = ENV.fetch('JABVOX_NGINX_SITES_DIR', '').freeze
    NGINX_RELOAD = ENV.fetch('JABVOX_NGINX_RELOAD_CMD', '').freeze

    def initialize(config)
      @config = config
      @domain = extract_domain(config.base_url_jabvox)
    end

    def call
      delete_cert_files
      delete_nginx_config
      reload_nginx if NGINX_RELOAD.present? && NGINX_SITES.present?
      @config.update!(
        base_url_jabvox: nil,
        ssl_status: 'none',
        ssl_cert: nil,
        ssl_key: nil,
        ssl_expires_at: nil,
        ssl_error: nil,
        ssl_provisioned_at: nil,
        acme_account_key: nil
      )
    end

    private

    VALID_DOMAIN_RE = /\A[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)+\z/i

    def extract_domain(raw)
      return nil if raw.blank?

      candidate = begin
        URI.parse(raw.strip).hostname.presence || raw.strip
      rescue URI::InvalidURIError
        raw.to_s.sub(%r{^https?://}, '').split('/').first.to_s.strip
      end
      candidate if candidate&.match?(VALID_DOMAIN_RE)
    end

    def delete_cert_files
      return if @domain.blank?

      domain_dir = File.join(CERTS_DIR, @domain)
      FileUtils.rm_rf(domain_dir) if Dir.exist?(domain_dir)
    end

    def delete_nginx_config
      return if @domain.blank? || NGINX_SITES.blank?

      conf_path = File.join(NGINX_SITES, "jabvox-ssl-#{@domain}.conf")
      File.delete(conf_path) if File.exist?(conf_path)
    end

    def reload_nginx
      output = `#{NGINX_RELOAD} 2>&1`
      Rails.logger.warn("Jabvox SSL revoke: nginx reload falló: #{output.strip}") unless $CHILD_STATUS.success?
    end
  end
end
