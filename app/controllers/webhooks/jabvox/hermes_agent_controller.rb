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
  before_action :authorize_source_ip!

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

  # Autentica por el token del HERMES (por conexión). Cada Hermes tiene su token de acción
  # único; resuelve la conexión → cuenta + el agente de la app ligado, y Hermes hereda los
  # permisos de ESE agente/usuario (si el usuario no puede algo, este token tampoco).
  #
  # Compatibilidad: si el token no corresponde a una conexión, se intenta como token de
  # agente (esquema anterior) para no romper integraciones ya repartidas.
  # Longitud máxima razonable de un token (secreto 24-byte b64 + sufijo). Rechaza payloads
  # absurdos antes de tocar la BD (defensa en profundidad contra sondas/DoS).
  MAX_TOKEN_LENGTH = 128

  def authenticate_agent!
    token = bearer_token.presence || request.headers['X-Hermes-Agent-Token'].to_s
    return head :unauthorized if token.blank? || token.length > MAX_TOKEN_LENGTH

    resolve_by_connection(token) || resolve_by_agent(token)

    # Requiere cuenta + usuario resueltos. authenticate() del modelo ya exige agente ACTIVO;
    # la conexión debe tener un agente/usuario ligado (sin ligar ⇒ no autentica).
    head :unauthorized if @account.nil? || @user.nil?
  end

  def resolve_by_connection(token)
    conn = JabvoxHermesConnection.authenticate_action(token)
    return false if conn.nil?

    @connection = conn
    @agent = conn.action_agent
    @account = conn.account
    @user = conn.action_user
    true
  end

  def resolve_by_agent(token)
    agent = JabvoxHermesAgent.authenticate(token)
    return false if agent.nil?

    @agent = agent
    @account = agent.account
    @user = agent.user
    true
  end

  # Segundo candado, tras el token: el request debe venir de una IP declarada por ESA
  # conexión (ver JabvoxHermesConnection#ip_allowed?). Un action_token filtrado no sirve
  # desde fuera del propio Hermes.
  #
  # Es FAIL-CLOSED: una conexión sin IPs declaradas no ejecuta nada. Eso incluye al esquema
  # antiguo de token-de-agente (sin conexión asociada), que no tiene allowlist y por tanto
  # ya no puede usarse para ejecutar: dejarlo pasar sería una puerta trasera que anula esta
  # verificación entera.
  #
  # Se valida la IP de la conexión TCP DIRECTA (request.remote_addr = REMOTE_ADDR de Rack),
  # NO request.remote_ip: este último deriva de X-Forwarded-For y sería falsificable por
  # cabeceras. Hermes llega directo a Jabvox (sin proxy intermedio), así que remote_addr es la
  # IP real del Hermes y no puede suplantarse con un header.
  def authorize_source_ip!
    return head :forbidden if @connection.nil?

    source_ip = request.remote_addr
    return if @connection.ip_allowed?(source_ip)

    Rails.logger.warn(
      "[HermesAgent] IP no autorizada connection_id=#{@connection.id} " \
      "account_id=#{@account&.id} ip=#{source_ip}"
    )
    head :forbidden
  end

  # Soporta Authorization: Bearer <token> además del header propio.
  def bearer_token
    auth = request.headers['Authorization'].to_s
    auth.start_with?('Bearer ') ? auth.split(' ', 2).last.to_s : ''
  end
end
