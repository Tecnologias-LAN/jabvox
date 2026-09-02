# frozen_string_literal: true

# Punto de entrada para que un AGENTE de Hermes ejecute acciones sobre Jabvox.
#
# Así se "conectan" los agentes de Hermes con los de Jabvox: cada agente Hermes tiene su
# TOKEN exclusivo (JabvoxHermesAgent#agent_token_jabvox). Hermes lo envía en el header; Jabvox
# resuelve QUÉ agente/usuario/cuenta es y ejecuta la tool con EXCLUSIVAMENTE los permisos de
# ese agente (los del usuario ligado). El LLM no puede intervenir el token ni escalar: la
# autorización ocurre aquí en backend (Authorizer + ToolExecutor), nunca en el prompt.
#
# Endpoint PÚBLICO (ActionController::API) blindado por el token de agente:
#   GET  /webhooks/jabvox/hermes_agent/tools   → lista las tools que este agente puede usar
#   POST /webhooks/jabvox/hermes_agent/execute  → ejecuta una tool { tool:, args: {} }
class Webhooks::Jabvox::HermesAgentController < ActionController::API
  before_action :authenticate_agent!

  # Tools que ESTE agente puede ejecutar (whitelist ya filtrada por permisos +
  # módulos). Devuelve tanto los nombres como las definiciones function-calling
  # (name/description/parameters) para que Hermes las registre como herramientas.
  def tools
    authorizer = Jabvox::Hermes::Authorizer.new(account: @account, user: @user)
    names = authorizer.allowed_tools
    definitions = names.filter_map { |n| Jabvox::Hermes::ToolRegistry.describe(n) }
    render json: {
      agent: @agent.name_jabvox,
      account_id: @account.id,
      execute_url: '/webhooks/jabvox/hermes_agent/execute',
      tools: names,
      definitions: definitions
    }
  end

  # Ejecuta una tool. La autorización (permiso del agente + módulo habilitado) y la política
  # de no-borrado se aplican dentro del ToolExecutor/ServiceLayer.
  def execute
    tool = params[:tool].to_s
    args = params[:args].respond_to?(:to_unsafe_h) ? params[:args].to_unsafe_h : (params[:args] || {})
    result = Jabvox::Hermes::ToolExecutor.new(account: @account, user: @user).execute(tool, args)

    if result.success?
      render json: { ok: true, data: result.data }
    elsif result.status == 'module_disabled'
      # Módulo no contratado/activo: respuesta clara y accionable para Hermes.
      render json: { ok: false, status: 'module_disabled', module: result.code, error: result.error },
             status: :forbidden
    else
      render json: { ok: false, status: result.status, error: result.error },
             status: result.status == 'forbidden' ? :forbidden : :unprocessable_entity
    end
  end

  private

  # Autentica por el token del agente (header). Resuelve agente activo → cuenta + usuario.
  def authenticate_agent!
    token = bearer_token.presence || request.headers['X-Hermes-Agent-Token'].to_s
    @agent = JabvoxHermesAgent.authenticate(token)
    return head :unauthorized if @agent.nil?

    @account = @agent.account
    @user = @agent.user
    head :unauthorized if @account.nil? || @user.nil?
  end

  # Soporta Authorization: Bearer <token> además del header propio.
  def bearer_token
    auth = request.headers['Authorization'].to_s
    auth.start_with?('Bearer ') ? auth.split(' ', 2).last.to_s : ''
  end
end
