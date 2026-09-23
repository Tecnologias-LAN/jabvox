# frozen_string_literal: true

# API por-cuenta de "Saldo IA": el admin de la cuenta ve su saldo (adquirido/gastado/restante)
# y crea/lista sus propias virtual keys contra el proveedor. Jabvox NO es proxy: la key se
# devuelve UNA sola vez al crearla y NUNCA se persiste; el cliente la usa directo contra el
# proveedor. Todo pasa por Jabvox::AiProvider::Client/BalanceService (nunca al proxy directo).
class Api::V1::Accounts::Jabvox::AiBudgetController < Api::V1::Accounts::Jabvox::BaseController
  # Gateado por el módulo de IA existente (no crea flags nuevos).
  jabvox_feature 'jabvox_ai_chat'
  include JabvoxPermissions

  # El proxy limita `size` a 100. MAX_KEY_PAGES acota el recorrido para que un team con
  # muchísimas keys no cuelgue la petición.
  KEYS_PAGE_SIZE = 100
  MAX_KEY_PAGES = 20

  before_action :ensure_admin

  # GET saldo de la cuenta (sin secretos). Refresca el gasto desde el proveedor si hay team.
  def show
    pa = provider_account
    Jabvox::AiProvider::BalanceService.new(Current.account).refresh_spend! if pa&.team_id_jabvox.present?
    render json: (pa&.reload&.summary || empty_summary)
  end

  # GET lista de virtual keys del team (metadatos, SIN la key en claro) + el catálogo de
  # modelos del proveedor y los del propio team, para poder asignarlos desde la UI.
  #
  # Devuelve TODAS las keys del team, las creara Jabvox o alguien directamente en el
  # proveedor: se recorren todas las páginas (el proxy pagina a 100 como máximo).
  def keys
    pa = provider_account
    return render json: { keys: [], available_models: [], team_models: [] } if pa.nil? || pa.team_id_jabvox.blank?

    client = Jabvox::AiProvider::Client.new
    rows, error = fetch_all_keys(client, pa.team_id_jabvox)
    return render json: { error: error }, status: :bad_gateway if error

    render json: { keys: rows,
                   available_models: client.model_names,
                   team_models: team_models(client, pa.team_id_jabvox) }
  end

  # POST crea una virtual key del team. La key se devuelve UNA sola vez y no se guarda.
  def create_key
    pa = provider_account
    if pa.nil? || pa.team_id_jabvox.blank?
      return render json: { error: 'La cuenta aún no tiene saldo de IA aprovisionado.' }, status: :unprocessable_entity
    end

    max_usd = params[:max_budget_usd]
    error = budget_error(pa, max_usd) || models_error(pa, params[:models])
    return render json: { error: error }, status: :unprocessable_entity if error

    resp = Jabvox::AiProvider::Client.new.generate_key(**new_key_params(pa, max_usd))
    return render json: { error: resp.error }, status: :bad_gateway unless resp.success?

    # La key en claro SOLO aquí. El cliente la guarda o la usa; Jabvox no la persiste.
    render json: { key: resp.data['key'], token_id: resp.data['token_id'],
                   note: 'Guárdala ahora: no se vuelve a mostrar. Se usa directamente contra el proveedor.' }
  end

  # POST bloquea una virtual key del team (deja de aceptar peticiones).
  def block_key
    with_own_key { |token| Jabvox::AiProvider::Client.new.block_key(token) }
  end

  # POST desbloquea una virtual key del team.
  def unblock_key
    with_own_key { |token| Jabvox::AiProvider::Client.new.unblock_key(token) }
  end

  # POST cambia el tope (max_budget) y/o los modelos de una virtual key del team.
  # Se puede enviar solo uno de los dos: lo que no viaja conserva su valor en el proveedor.
  def update_key
    max_usd = params[:max_budget_usd]
    models = params[:models]
    error = update_key_error(max_usd, models)
    return render json: { error: error }, status: :unprocessable_entity if error

    with_own_key do |token|
      Jabvox::AiProvider::Client.new.update_key(
        token,
        max_budget_usd: max_usd.present? ? max_usd.to_f : nil,
        models: models.nil? ? nil : Array(models).map(&:to_s)
      )
    end
  end

  private

  # Parámetros de la key nueva. El team sale SIEMPRE del registro de la cuenta (servidor),
  # nunca de params: así una cuenta no puede crear keys en el team de otra.
  def new_key_params(provider_account, max_usd)
    { team_id: provider_account.team_id_jabvox,
      key_alias: params[:key_alias].presence || "cuenta-#{Current.account.id}-#{Time.current.to_i}",
      models: Array(params[:models]).map(&:to_s),
      max_budget_usd: max_usd.present? ? max_usd.to_f : nil,
      metadata: { 'crm_id' => Current.account.id.to_s } }
  end

  # Recorre todas las páginas de /key/list. El proxy limita `size` a 100, así que un team
  # con más keys perdía el resto (y una key creada fuera de Jabvox podía caer en la página
  # que nunca se pedía). Devuelve [filas_saneadas, error].
  def fetch_all_keys(client, team_id)
    rows = []
    page = 1
    loop do
      resp = client.list_keys(team_id, page: page, size: KEYS_PAGE_SIZE)
      return [[], resp.error] unless resp.success?

      rows.concat(sanitize_keys(resp.data))
      total_pages = resp.data.is_a?(Hash) ? resp.data['total_pages'].to_i : 1
      break if page >= [total_pages, MAX_KEY_PAGES].min

      page += 1
    end
    [rows, nil]
  end

  # Modelos a los que está limitado el team. [] = sin restricción (todos los del proxy).
  def team_models(client, team_id)
    resp = client.team_info(team_id)
    return [] unless resp.success?

    info = resp.data.is_a?(Hash) ? (resp.data['team_info'] || resp.data) : {}
    Array(info['models']).map(&:to_s)
  end

  # Valida los modelos pedidos para una key. Devuelve el mensaje de error, o nil.
  #
  # Una key nunca puede acceder a más modelos que su team: si el team está restringido a una
  # lista, pedir uno fuera de ella sería escalar privilegios desde la cuenta. Si el team no
  # restringe (lista vacía), se valida contra el catálogo real del proxy para no aceptar
  # nombres inventados.
  def models_error(provider_account, models)
    requested = Array(models).map(&:to_s).reject(&:blank?)
    return nil if requested.empty? # [] = sin restricción, hereda del team

    allowed = allowed_models_for(provider_account)
    return nil if allowed.empty? # el proxy no reporta catálogo: no inventar un bloqueo

    invalid = requested - allowed
    invalid.empty? ? nil : "Modelos no permitidos para esta cuenta: #{invalid.join(', ')}."
  end

  # Modelos que la cuenta puede asignar: los del team si está restringido, si no, el
  # catálogo completo del proxy.
  def allowed_models_for(provider_account)
    client = Jabvox::AiProvider::Client.new
    allowed = team_models(client, provider_account&.team_id_jabvox)
    allowed.presence || client.model_names
  end

  # Valida tope y modelos de update_key. Devuelve el mensaje de error, o nil.
  def update_key_error(max_usd, models)
    return 'Indica un tope válido.' if max_usd.blank? && models.nil?

    pa = provider_account
    return nil if pa.nil?

    budget_error(pa, max_usd) || (models.nil? ? nil : models_error(pa, models))
  end

  # Valida el tope pedido para una key. Devuelve el mensaje de error, o nil si es válido.
  #
  # El tope de una key no puede exceder el del team, PERO si el team es ilimitado (sin
  # max_budget en el proveedor y sin saldo asignado en Jabvox) no hay techo que exceder:
  # comparar contra su total de 0 rechazaba toda key con tope.
  def budget_error(provider_account, max_usd)
    return nil if max_usd.blank?
    return 'El tope debe ser mayor que cero.' if max_usd.to_f <= 0
    return nil if provider_account.unlimited_budget?
    return nil if max_usd.to_f <= provider_account.total_budget_usd

    "El tope de la key (#{max_usd}) excede el saldo del team (#{provider_account.total_budget_usd})."
  end

  # Ejecuta la acción SOLO si el token indicado pertenece al team de ESTA cuenta.
  #
  # Aislamiento multi-cuenta: el token llega en params (controlado por el llamador), así que
  # nunca se usa directo contra el proveedor. Se listan las keys del team de la cuenta actual
  # —resuelto en servidor desde Current.account, nunca desde params— y se exige que el token
  # esté entre ellas. Sin esto, un admin podría bloquear o re-topear la key de otra cuenta
  # conociendo su hash.
  def with_own_key
    pa = provider_account
    if pa.nil? || pa.team_id_jabvox.blank?
      return render json: { error: 'La cuenta aún no tiene saldo de IA aprovisionado.' },
                    status: :unprocessable_entity
    end

    token = params[:token_id].to_s
    return render json: { error: 'Falta la key.' }, status: :unprocessable_entity if token.blank?
    return render json: { error: 'Esa key no pertenece a esta cuenta.' }, status: :not_found unless team_key?(pa, token)

    resp = yield(token)
    return render json: { error: resp.error }, status: :bad_gateway unless resp.success?

    render json: { success: true }
  end

  # ¿El token pertenece al team de la cuenta? Se compara contra la lista real del proveedor.
  def team_key?(provider_account, token)
    resp = Jabvox::AiProvider::Client.new.list_keys(provider_account.team_id_jabvox)
    return false unless resp.success?

    raw = resp.data.is_a?(Hash) ? (resp.data['keys'] || []) : Array(resp.data)
    Array(raw).any? do |k|
      candidates = k.is_a?(Hash) ? [k['token'], k['token_id'], k['key_name']] : [k]
      candidates.compact.map(&:to_s).include?(token)
    end
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Solo administradores de la cuenta.' }, status: :forbidden
  end

  def provider_account
    JabvoxAiProviderAccount.find_by(account_id: Current.account.id)
  end

  def empty_summary
    { account_id: Current.account.id, connected: false }
  end

  # Nunca devuelve la key en claro (el proveedor tampoco la devuelve en /key/list): solo
  # metadatos. `token_id` es el HASH de la key — sirve para bloquear/re-topear sin que
  # Jabvox llegue a conocer ni almacenar el secreto.
  #
  # Con `return_full_object=true` el proveedor devuelve objetos; sin él, strings sueltos
  # (el propio token). Se contemplan ambas formas para no romper si cambia el parámetro.
  def sanitize_keys(data)
    list = data.is_a?(Hash) ? (data['keys'] || data['data'] || []) : Array(data)
    Array(list).map { |k| sanitize_key(k) }
  end

  def sanitize_key(key)
    # Sin `return_full_object` el proveedor devuelve el token suelto en vez del objeto.
    return { alias: nil, token_id: key.to_s, spend: nil, max_budget: nil, blocked: false } unless key.is_a?(Hash)

    { alias: key['key_alias'], token_id: key['token'] || key['token_id'],
      spend: key['spend'], max_budget: key['max_budget'],
      # [] = la key no restringe modelos y hereda los del team.
      models: Array(key['models']).map(&:to_s),
      blocked: ActiveModel::Type::Boolean.new.cast(key['blocked']) || false }
  end
end
