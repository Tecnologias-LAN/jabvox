# frozen_string_literal: true

# Registro declarativo de las tools que Hermes puede ejecutar sobre Jabvox.
#
# Cada tool declara: el permiso requerido, el endpoint interno (método + path relativo a
# /api/v1/accounts/:account_id), y un esquema mínimo de parámetros. Es la ÚNICA fuente de
# verdad de "qué tools existen y qué permiso piden" — el LLM nunca inventa tools ni permisos.
#
# Doble autorización (se valida en HermesAuthorizer, no aquí):
#   NIVEL 1: la cuenta tiene habilitada la tool/MCP.
#   NIVEL 2: el usuario tiene el permiso requerido.
module Jabvox::Hermes::ToolRegistry
  module_function

  # tool_name => { permission:, method:, path:, params:, mcp:, feature: }
  # `path` admite :id como placeholder. `mcp` agrupa la tool bajo un MCP lógico (NIVEL 1).
  # `feature` es el módulo jabvox que la gatea (NIVEL 1.5); 'core' = funcionalidad base sin
  # gate de módulo. TODAS las áreas son de la cuenta y NINGUNA borra (solo read/create/write).
  TOOLS = {
    # --- Etiquetas (labels) — core ---
    'get_labels' => { permission: 'read', method: :get, path: 'labels', mcp: 'jabvox_core', feature: 'core' },
    'create_label' => { permission: 'create', method: :post, path: 'labels',
                        params: { title: :string }, mcp: 'jabvox_core', feature: 'core' },
    'update_label' => { permission: 'write', method: :patch, path: 'labels/:id',
                        params: { id: :integer, title: :string }, mcp: 'jabvox_core', feature: 'core' },

    # --- Bandejas (inboxes) — core, solo lectura (crear inbox es sensible/infra) ---
    'get_inboxes' => { permission: 'read', method: :get, path: 'inboxes', mcp: 'jabvox_core', feature: 'core' },

    # --- Contactos — core ---
    'search_contacts' => { permission: 'read', method: :get, path: 'contacts/search',
                           params: { q: :string }, mcp: 'jabvox_core', feature: 'core' },
    'get_contact' => { permission: 'read', method: :get, path: 'contacts/:id',
                       params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'create_contact' => { permission: 'create', method: :post, path: 'contacts',
                          params: { name: :string, email: :string, phone_number: :string },
                          mcp: 'jabvox_core', feature: 'core' },
    'update_contact' => { permission: 'write', method: :patch, path: 'contacts/:id',
                          params: { id: :integer, name: :string, email: :string, phone_number: :string },
                          mcp: 'jabvox_core', feature: 'core' },

    # --- Conversaciones + mensajes — core ---
    'get_conversations_meta' => { permission: 'read', method: :get, path: 'conversations/meta',
                                  mcp: 'jabvox_core', feature: 'core' },
    'get_conversation_messages' => { permission: 'read', method: :get, path: 'conversations/:id/messages',
                                     params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'reply_conversation' => { permission: 'write', method: :post, path: 'conversations/:id/messages',
                              params: { id: :integer, content: :string }, mcp: 'jabvox_core', feature: 'core' },
    # Nota privada de una conversación (mensaje interno, no visible al cliente).
    'add_private_note' => { permission: 'create', method: :post, path: 'conversations/:id/notes',
                            params: { id: :integer, content: :string }, mcp: 'jabvox_core', feature: 'core' },

    # --- Notas de contacto — core ---
    'get_contact_notes' => { permission: 'read', method: :get, path: 'contacts/:id/notes',
                             params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'create_contact_note' => { permission: 'create', method: :post, path: 'contacts/:id/notes',
                               params: { id: :integer, content: :string }, mcp: 'jabvox_core', feature: 'core' },

    # --- Automatizaciones — core (flujos de automatización) ---
    'get_automation_rules' => { permission: 'read', method: :get, path: 'automation_rules',
                                mcp: 'jabvox_core', feature: 'core' },
    'create_automation_rule' => { permission: 'create', method: :post, path: 'automation_rules',
                                  params: { name: :string, event_name: :string,
                                            conditions: :json, actions: :json },
                                  mcp: 'jabvox_core', feature: 'core' },
    'update_automation_rule' => { permission: 'write', method: :patch, path: 'automation_rules/:id',
                                  params: { id: :integer, name: :string, active: :boolean,
                                            conditions: :json, actions: :json },
                                  mcp: 'jabvox_core', feature: 'core' },

    # --- Integración por WEBHOOK directo al Hermes de la cuenta (así responde bandejas) ---
    # Hermes NO es un AgentBot de Jabvox: se integra como un webhook. Jabvox dispara el evento
    # message_created hacia el Hermes de ESTA cuenta (URL fijada por Jabvox, no por el LLM);
    # el Hermes recibe el mensaje, razona y responde llamando de vuelta a reply_conversation.
    'get_webhooks' => { permission: 'read', method: :get, path: 'webhooks',
                        mcp: 'jabvox_core', feature: 'core' },
    # Crea la integración de webhook Hermes para TODAS las bandejas (account_type).
    'create_hermes_webhook' => { permission: 'create', method: :post, path: 'webhooks',
                                 params: {}, mcp: 'jabvox_core', feature: 'core' },
    # Crea la integración de webhook Hermes para UNA bandeja concreta (inbox_type).
    'create_hermes_inbox_webhook' => { permission: 'create', method: :post, path: 'webhooks/inbox',
                                       params: { inbox_id: :integer }, mcp: 'jabvox_core', feature: 'core' },

    # --- Leads (módulo leads) ---
    'search_leads' => { permission: 'read', method: :get, path: 'jabvox/leads',
                        params: { q: :string }, mcp: 'jabvox_leads', feature: 'core' },
    'get_lead' => { permission: 'read', method: :get, path: 'jabvox/leads/:id',
                    params: { id: :integer }, mcp: 'jabvox_leads', feature: 'core' },

    # --- Gestiones (management states) ---
    'get_management_states' => { permission: 'read', method: :get, path: 'jabvox/management_states',
                                 mcp: 'jabvox_management', feature: 'core' },
    'create_management_state' => { permission: 'create', method: :post, path: 'jabvox/management_states',
                                   params: { name: :string }, mcp: 'jabvox_management', feature: 'core' },
    'update_management_state' => { permission: 'write', method: :patch, path: 'jabvox/management_states/:id',
                                   params: { id: :integer, name: :string }, mcp: 'jabvox_management', feature: 'core' },

    # --- Campañas del dialer (gateado por jabvox_dialer) ---
    'get_dialer_campaigns' => { permission: 'read', method: :get, path: 'jabvox/dialer_campaigns',
                                mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'get_dialer_campaign' => { permission: 'read', method: :get, path: 'jabvox/dialer_campaigns/:id',
                               params: { id: :integer }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'create_dialer_campaign' => { permission: 'create', method: :post, path: 'jabvox/dialer_campaigns',
                                  params: { name: :string }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'update_dialer_campaign' => { permission: 'write', method: :patch, path: 'jabvox/dialer_campaigns/:id',
                                  params: { id: :integer, name: :string }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },

    # --- Envíos masivos: SMS (jabvox_sms) ---
    'get_sms_campaigns' => { permission: 'read', method: :get, path: 'jabvox/sms_campaigns',
                             mcp: 'jabvox_sms', feature: 'jabvox_sms' },
    'create_sms_campaign' => { permission: 'create', method: :post, path: 'jabvox/sms_campaigns',
                               params: { name: :string, message: :string },
                               mcp: 'jabvox_sms', feature: 'jabvox_sms' },
    'update_sms_campaign' => { permission: 'write', method: :patch, path: 'jabvox/sms_campaigns/:id',
                               params: { id: :integer, name: :string, message: :string },
                               mcp: 'jabvox_sms', feature: 'jabvox_sms' },

    # --- Reportes de la cuenta (solo lectura) ---
    'get_report_summary' => { permission: 'read', method: :get, path: 'jabvox/reports/agents',
                              mcp: 'analytics', feature: 'core' }
  }.freeze

  # Métodos HTTP y permisos prohibidos por política. Ninguna tool puede borrar.
  FORBIDDEN_METHODS = %i[delete].freeze
  FORBIDDEN_PERMISSIONS = %w[delete destroy].freeze

  # Garantiza en tiempo de carga que ninguna tool sea destructiva. Falla ruidosamente si
  # alguien introduce una tool :delete: la seguridad no depende de recordar la política.
  def assert_no_destructive_tools!
    offenders = TOOLS.select do |_name, spec|
      FORBIDDEN_METHODS.include?(spec[:method]) ||
        FORBIDDEN_PERMISSIONS.include?(spec[:permission])
    end
    return if offenders.empty?

    raise "Tools destructivas prohibidas en ToolRegistry: #{offenders.keys.join(', ')}"
  end

  def all
    TOOLS
  end

  def find(tool_name)
    TOOLS[tool_name.to_s]
  end

  def exists?(tool_name)
    TOOLS.key?(tool_name.to_s)
  end

  # Permiso requerido por una tool (o nil si no existe).
  def permission_for(tool_name)
    find(tool_name)&.fetch(:permission, nil)
  end

  # MCP lógico al que pertenece la tool (para el gating por cuenta).
  def mcp_for(tool_name)
    find(tool_name)&.fetch(:mcp, nil)
  end
end
