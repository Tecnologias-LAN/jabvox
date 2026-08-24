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

  # tool_name => { permission:, method:, path:, params:, mcp: }
  # `path` admite :id como placeholder que se sustituye con params. `mcp` agrupa la tool
  # bajo un MCP lógico (para el gating por cuenta en NIVEL 1).
  TOOLS = {
    # --- Etiquetas (labels) ---
    'get_labels' => { permission: 'read', method: :get, path: 'labels', mcp: 'jabvox_core' },
    'create_label' => { permission: 'create', method: :post, path: 'labels',
                        params: { title: :string }, mcp: 'jabvox_core' },
    'update_label' => { permission: 'write', method: :patch, path: 'labels/:id',
                        params: { id: :integer, title: :string }, mcp: 'jabvox_core' },
    'delete_label' => { permission: 'delete', method: :delete, path: 'labels/:id',
                        params: { id: :integer }, mcp: 'jabvox_core' },
    # --- Conversaciones (lectura + responder) ---
    'get_conversations_meta' => { permission: 'read', method: :get, path: 'conversations/meta',
                                  mcp: 'jabvox_core' },
    'reply_conversation' => { permission: 'write', method: :post, path: 'conversations/:id/messages',
                              params: { id: :integer, content: :string }, mcp: 'jabvox_core' },
    # --- Analítica (solo lectura) ---
    'get_report_summary' => { permission: 'read', method: :get, path: 'jabvox/reports/agents',
                              mcp: 'analytics' }
  }.freeze

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
