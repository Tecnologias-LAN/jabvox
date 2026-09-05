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
  Result = Struct.new(:status, :data, :error, :code, keyword_init: true) do
    def success? = status == 'success'
  end

  # Nombre legible por módulo (feature flag) para los mensajes que Hermes le
  # traslada al usuario cuando un módulo no está habilitado.
  MODULE_LABELS = {
    'jabvox_dialer' => 'Marcador (Dialer)',
    'jabvox_sms' => 'Campañas SMS',
    'jabvox_audio_analysis' => 'Análisis de Audio',
    'jabvox_analytics' => 'Analytics y Dashboards',
    'jabvox_cdr' => 'Reportes CDR',
    'jabvox_products' => 'Productos y Pedidos',
    'jabvox_calendar' => 'Calendario',
    'jabvox_tasks' => 'Tareas',
    'jabvox_bulk_whatsapp' => 'Envíos masivos de WhatsApp',
    'jabvox_leads' => 'Leads',
    'jabvox_kanban' => 'Kanban'
  }.freeze

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
    # El detalle real (mensaje/clase) SOLO se audita en el backend; a Hermes se le devuelve
    # un mensaje genérico y accionable — nunca nombres de tablas, SQL ni trazas internas.
    audit(tool: tool_name, permission: Jabvox::Hermes::ToolRegistry.permission_for(tool_name), status: 'error',
          params: args, error: e, started: started)
    Result.new(status: 'error', error: client_error_message(e))
  end

  private

  # Traduce una excepción interna a un mensaje seguro para el cliente (Hermes). No revela
  # detalles de implementación; solo lo justo para que el usuario sepa qué pasó.
  def client_error_message(error)
    case error
    when ActiveRecord::RecordNotFound
      'No se encontró el registro solicitado.'
    when ActiveRecord::RecordInvalid
      # Los mensajes de validación son de negocio (ej. "el nombre no puede estar en blanco")
      # y sí son útiles y seguros de mostrar.
      error.record.errors.full_messages.first || 'Datos inválidos.'
    when ActiveRecord::RecordNotSaved, ArgumentError
      'No se pudo completar la acción con los datos proporcionados.'
    else
      'No se pudo completar la acción. Intenta de nuevo o contacta al administrador.'
    end
  end

  # Ejecuta la acción llamando a la capa de servicio interna de Jabvox. Aquí se enruta
  # cada tool a su servicio/endpoint controlado. NUNCA hay SQL ni acceso directo a BD:
  # se delega en los servicios de dominio existentes, que aplican sus propias reglas.
  def dispatch(spec, params)
    Jabvox::Hermes::ServiceLayer.new(account: @account, user: @user, hermes_name: @identity&.name_jabvox).call(
      method: spec[:method], path: resolve_path(spec[:path], params), params: params
    )
  end

  # Sustituye :id (y otros placeholders) en el path con los params ya validados.
  def resolve_path(path, params)
    path.gsub(/:(\w+)/) { params[Regexp.last_match(1).to_sym].to_s }
  end

  # Coacciona tipos declarados y descarta lo no declarado (whitelist de params: el LLM no
  # puede colar campos extra). Tipos: :string, :integer, :boolean, :json (hash/array).
  def coerce_params(spec, args)
    schema = spec[:params] || {}
    args = args.transform_keys(&:to_sym)
    schema.each_with_object({}) do |(key, type), out|
      next unless args.key?(key)

      out[key] = coerce_value(type, args[key])
    end
  end

  def coerce_value(type, value)
    case type
    when :integer then value.to_i
    when :boolean then ActiveModel::Type::Boolean.new.cast(value)
    when :json then value.is_a?(String) ? safe_json(value) : value
    else value.to_s
    end
  end

  def safe_json(str)
    JSON.parse(str)
  rescue JSON::ParserError
    str
  end

  def forbidden(tool_name, decision, started)
    audit(tool: tool_name, permission: decision.permission, status: 'forbidden',
          error: decision.reason, started: started)
    # Cuando la denegación es por MÓDULO no habilitado, damos un status y mensaje
    # accionable para que Hermes se lo diga al usuario ("contacta al administrador
    # para adquirirlo"), en vez de un genérico "prohibido".
    if decision.code == 'module_disabled'
      label = MODULE_LABELS[decision.feature] || decision.feature
      msg = "El módulo \"#{label}\" no está habilitado en esta cuenta. " \
            'Contacta al administrador de la cuenta para adquirirlo/activarlo.'
      return Result.new(status: 'module_disabled', code: decision.feature, error: msg)
    end

    Result.new(status: 'forbidden', code: decision.code, error: decision.reason)
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
