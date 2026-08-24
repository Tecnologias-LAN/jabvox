# frozen_string_literal: true

# Chat Aprovisionamiento: interpreta lo que pide el usuario y crea MCPs en ContextForge
# para SU cuenta, o guía a aprovisionar / rutea a Hermes. Opera solo sobre el handoff de
# la cuenta; nunca expone el token.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  class ProvisioningChatService
    # Catálogo de MCPs que el usuario puede pedir por lenguaje natural.
    KNOWN_KINDS = {
      'analytics' => { kind: 'analytics_db', name: 'Analytics DB (cuenta)' },
      'analitic' => { kind: 'analytics_db', name: 'Analytics DB (cuenta)' },
      'reporte' => { kind: 'reports', name: 'Reportes (cuenta)' },
      'report' => { kind: 'reports', name: 'Reportes (cuenta)' },
      'base de datos' => { kind: 'external_db', name: 'Base de datos externa (cuenta)' },
      'database' => { kind: 'external_db', name: 'Base de datos externa (cuenta)' }
    }.freeze

    def initialize(account:, user:, service: ContextForge::Service.new)
      @account = account
      @user = user
      @service = service
    end

    # @return [Hash] { reply:, metadata: }
    def handle(content)
      # Arquitectura nueva: la cuenta ligada al Hermes Aprovisionador global le pide cosas a
      # ESE Hermes (que ya sabe crear/ligar el Hermes de la cuenta). Jabvox no toca ContextForge.
      return route_to_provisioner(content) if JabvoxHermesProvisionerLink.active_for?(@account.id)

      # Compatibilidad: modo antiguo por ContextForge directo (si la cuenta lo usa).
      handoff = @account.jabvox_context_forge_handoff
      return reply(no_handoff_msg) if handoff.nil? || !handoff.operational?

      requested = detect_mcp_request(content)
      return create_mcp(handoff, requested) if requested

      route_to_hermes(handoff, content)
    rescue StandardError => e
      Rails.logger.error("[ProvisioningChat] account=#{@account.id} error=#{e.class}")
      reply("Ocurrió un error procesando tu solicitud: #{e.message}")
    end

    # Envía el mensaje al Hermes Aprovisionador global (el que aprovisiona instancias). El
    # aprovisionador razona y ejecuta con sus MCPs de infraestructura; Jabvox solo transporta.
    def route_to_provisioner(content)
      result = Jabvox::Hermes::ProvisionerChatRelay.new(account: @account, user: @user).send_message(content)
      if result.success?
        reply(result.text, metadata: { via: 'provisioner' })
      else
        reply("El aprovisionador no pudo responder: #{result.error}", metadata: { via: 'provisioner', ok: false })
      end
    end

    private

    # Detecta "crea/nuevo mcp de <algo>" y devuelve el descriptor, o nil.
    def detect_mcp_request(content)
      text = content.to_s.downcase
      return nil unless text.match?(/\b(crea|crear|nuevo|nueva|agrega|añade|add|create)\b/) && text.include?('mcp')

      KNOWN_KINDS.each { |kw, desc| return desc if text.include?(kw) }
      # mcp genérico si no matchea un tipo conocido
      { kind: "custom_#{Time.current.to_i}", name: 'MCP personalizado (cuenta)' }
    end

    def create_mcp(handoff, desc)
      res = @service.ensure_mcp_server(@account, team_id: handoff.team_id,
                                                 kind: desc[:kind], name: desc[:name])
      unless res.success?
        return reply("No pude crear el MCP '#{desc[:name]}': #{res.error}",
                     metadata: { action: 'create_mcp', ok: false, kind: desc[:kind] })
      end

      mcp_id = res.data.is_a?(Hash) ? (res.data['id'] || res.data['external_id']) : res.data
      attach_to_virtual_server
      record_mcp(handoff, desc[:kind])
      reply("Listo: creé el MCP '#{desc[:name]}' y lo agregué a tu servidor. Ya está disponible en tu Chat IA.",
            metadata: { action: 'create_mcp', ok: true, kind: desc[:kind], mcp_id: mcp_id })
    end

    # Reincluye TODAS las MCPs de la cuenta en su virtual server (idempotente): delega en
    # el provisioner, que reconcilia MCPs + virtual server + token por external_id estable.
    def attach_to_virtual_server
      ContextForge::AccountProvisioner.new(@account, service: @service).call
    end

    def record_mcp(handoff, kind)
      mcps = handoff.mcp_servers || []
      mcps << { 'kind' => kind, 'ok' => true } unless mcps.any? { |m| m['kind'] == kind }
      handoff.update!(mcp_servers: mcps)
    end

    # Rutea el mensaje al Hermes Provisioner de la cuenta (OpenAI-compat) si hay URL.
    def route_to_hermes(_handoff, content)
      hermes_url = ContextForge::Service.hermes_url
      return reply(help_msg(content)) if hermes_url.blank?

      # El puente real con Hermes se hace vía su endpoint chat-completions; sin Hermes
      # vivo respondemos con ayuda en vez de simular una respuesta del modelo.
      reply(help_msg(content), metadata: { routed: 'hermes', hermes_url_present: true })
    end

    def no_handoff_msg
      'Tu cuenta aún no está aprovisionada. Pulsa "Aprovisionar mi cuenta" para crear tu ' \
        'entorno Hermes/ContextForge y sus MCPs por defecto.'
    end

    def help_msg(_content)
      'Puedo crear MCPs para tu cuenta. Por ejemplo: "crea un MCP de analytics" o ' \
        '"nuevo MCP de reportes". También puedes pedir un MCP de base de datos externa.'
    end

    def reply(text, metadata: {})
      { reply: text, metadata: metadata }
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
