# frozen_string_literal: true

# Conexión directa a un Hermes (sin ContextForge). El usuario pega la URL de su Hermes;
# Jabvox arma el prompt de auto-aprovisionamiento (URL de Jabvox + account_id + token de
# admin de la cuenta) para pegarlo en el chat de Hermes, igual que Hermes se integraría
# con Telegram o Chatwoot.
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

      token = admin_token
      return failure('No se pudo obtener el token de admin de la cuenta.') if token.blank?

      handoff = persist(token)
      Result.new(success: true, handoff: handoff, prompt: build_prompt(token))
    rescue StandardError => e
      failure(e.message)
    end

    # Prompt de aprovisionamiento (para copiar y pegar en Hermes). Se puede regenerar.
    def self.prompt_for(account, user, hermes_url)
      new(account: account, user: user, hermes_url: hermes_url).send(:build_prompt, nil)
    end

    private

    def valid_url?(url)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def admin_token
      @user.access_token&.token || @user.create_access_token&.token
    end

    def persist(token)
      handoff = JabvoxContextForgeHandoff.find_or_create_by!(account_id: @account.id)
      handoff.mark_ready!(hermes_url: @hermes_url, scoped_token: token, mcp_servers: [])
      handoff
    end

    def build_prompt(token)
      <<~PROMPT.strip
        Conéctate a este CRM Jabvox y auto-aprovisiónate para la cuenta indicada.
        Usa la API de Jabvox (compatible con el estilo Chatwoot) con estos datos:

        - Jabvox base URL: #{jabvox_base_url}
        - account_id: #{@account.id}
        - api_access_token (admin de la cuenta): #{token || '<se mostrará al conectar>'}

        Autentícate enviando el header `api_access_token: <token>` en cada request.
        Endpoints principales por cuenta (prefijo /api/v1/accounts/#{@account.id}):
        - Responder en una conversación: POST .../conversations/{id}/messages  body {content}
        - Nota privada: POST .../conversations/{id}/messages  body {content, private: true}
        - Cambiar estado: POST .../conversations/{id}/toggle_status
        Trabaja SOLO sobre la cuenta #{@account.id}. No accedas a otras cuentas.
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
