# frozen_string_literal: true

# Conexión directa a un Hermes (sin ContextForge). El usuario pega la URL de su Hermes y
# Jabvox registra el handoff con una IDENTIDAD DE SERVICIO propia de la cuenta.
#
# FASE 0 (seguridad): ya NO se entrega el api_access_token de admin de la cuenta dentro de
# un prompt de texto plano. En su lugar Hermes usa el token de servicio de la identidad de
# la cuenta (jabvox_hermes_identities), que se transmite por canal seguro (header) en la
# capa de ejecución y se valida en backend forzando el account_id + permisos. El prompt de
# aprovisionamiento NUNCA contiene credenciales.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  class HermesConnectionService
    Result = Struct.new(:success, :handoff, :prompt, :error, keyword_init: true) do
      def success? = success
    end

    def initialize(account:, user:, hermes_url:)
      @account = account
      @user = user
      @hermes_url = hermes_url.to_s.strip
    end

    def call
      return failure('La URL de Hermes es requerida.') if @hermes_url.blank?
      return failure('URL de Hermes inválida.') unless valid_url?(@hermes_url)

      identity = JabvoxHermesIdentity.for_account(@account)
      handoff = persist(identity)
      Result.new(success: true, handoff: handoff, prompt: build_prompt)
    rescue StandardError => e
      failure(e.message)
    end

    # Prompt de aprovisionamiento (para copiar y pegar en Hermes). SIN credenciales.
    def self.prompt_for(account, user, hermes_url)
      new(account: account, user: user, hermes_url: hermes_url).send(:build_prompt)
    end

    private

    def valid_url?(url)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    # Guarda el handoff con el TOKEN DE SERVICIO de la identidad de la cuenta (no el token
    # admin de un usuario). El token se almacena cifrado (ver JabvoxContextForgeHandoff).
    def persist(identity)
      handoff = JabvoxContextForgeHandoff.find_or_create_by!(account_id: @account.id)
      handoff.mark_ready!(hermes_url: @hermes_url, scoped_token: identity.service_token.token, mcp_servers: [])
      handoff
    end

    # Prompt SIN token. Solo describe cómo conectarse; la credencial viaja por header en la
    # capa de ejecución, nunca en el texto del prompt.
    def build_prompt
      <<~PROMPT.strip
        Conéctate a este CRM Jabvox para la cuenta indicada.

        - Jabvox base URL: #{jabvox_base_url}
        - account_id: #{@account.id}

        La credencial de servicio se te entrega por el header `api_access_token` en cada
        request (NUNCA en este texto). Autentícate con ese header.

        Trabaja SOLO sobre la cuenta #{@account.id} y ÚNICAMENTE mediante las tools/MCP
        autorizadas. No accedas a otras cuentas ni a la base de datos directamente.
      PROMPT
    end

    def jabvox_base_url
      ENV['FRONTEND_URL'].to_s.strip.presence || 'https://app.jabvox.co'
    end

    def failure(msg)
      Result.new(success: false, error: msg)
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
