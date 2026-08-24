# frozen_string_literal: true

# Ejecuta una tool de Hermes de forma segura:
#   1. Autoriza (doble control) vía HermesAuthorizer — rechaza si el usuario no puede.
#   2. Valida/coacciona los parámetros contra el esquema del registro.
#   3. Ejecuta la acción contra la CAPA DE SERVICIO interna (nunca SQL, nunca la BD directa).
#   4. Audita SIEMPRE el resultado (éxito, prohibido o error) sin guardar secretos.
#
# Este es el punto donde "el backend rechaza aunque el LLM quiera ejecutar": la decisión de
# autorización ocurre aquí, en Ruby, no en el prompt.
class Jabvox::Hermes::ToolExecutor
  Result = Struct.new(:status, :data, :error, keyword_init: true) do
    def success? = status == 'success'
  end

  def initialize(account:, user:)
    @account = account
    @user = user
    @authorizer = Jabvox::Hermes::Authorizer.new(account: account, user: user)
    @identity = JabvoxHermesIdentity.for_account(account)
  end

  # tool_name: string · args: hash de parámetros propuestos por el LLM.
  def execute(tool_name, args = {})
    started = monotonic_ms
    decision = @authorizer.authorize(tool_name)
    return forbidden(tool_name, decision, started) unless decision.allowed?

    spec = Jabvox::Hermes::ToolRegistry.find(tool_name)
    params = coerce_params(spec, args)
    data = dispatch(spec, params)
    audit(tool: tool_name, permission: decision.permission, status: 'success', params: params, started: started)
    Result.new(status: 'success', data: data)
  rescue StandardError => e
    audit(tool: tool_name, permission: Jabvox::Hermes::ToolRegistry.permission_for(tool_name), status: 'error',
          params: args, error: e, started: started)
    Result.new(status: 'error', error: e.message)
  end

  private

  # Ejecuta la acción llamando a la capa de servicio interna de Jabvox. Aquí se enruta
  # cada tool a su servicio/endpoint controlado. NUNCA hay SQL ni acceso directo a BD:
  # se delega en los servicios de dominio existentes, que aplican sus propias reglas.
  def dispatch(spec, params)
    Jabvox::Hermes::ServiceLayer.new(account: @account, user: @user).call(
      method: spec[:method], path: resolve_path(spec[:path], params), params: params
    )
  end

  # Sustituye :id (y otros placeholders) en el path con los params ya validados.
  def resolve_path(path, params)
    path.gsub(/:(\w+)/) { params[Regexp.last_match(1).to_sym].to_s }
  end

  # Coacciona tipos declarados (string/integer) y descarta lo no declarado (whitelist de
  # params: el LLM no puede colar campos extra).
  def coerce_params(spec, args)
    schema = spec[:params] || {}
    args = args.transform_keys(&:to_sym)
    schema.each_with_object({}) do |(key, type), out|
      next unless args.key?(key)

      out[key] = type == :integer ? args[key].to_i : args[key].to_s
    end
  end

  def forbidden(tool_name, decision, started)
    audit(tool: tool_name, permission: decision.permission, status: 'forbidden',
          error: decision.reason, started: started)
    Result.new(status: 'forbidden', error: decision.reason)
  end

  # entry: { tool:, permission:, status:, params: {}, error: nil, started: }
  def audit(entry)
    JabvoxHermesActionLog.record!(
      account_id: @account.id, user_id: @user&.id, hermes_identity: @identity.name_jabvox,
      tool: entry[:tool], permission: entry[:permission], status: entry[:status],
      params: entry[:params] || {}, error: entry[:error],
      duration_ms: monotonic_ms - entry[:started]
    )
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
  end
end
