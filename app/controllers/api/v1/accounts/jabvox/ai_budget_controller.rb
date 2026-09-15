# frozen_string_literal: true

# API por-cuenta de "Saldo IA": el admin de la cuenta ve su saldo (adquirido/gastado/restante)
# y crea/lista sus propias virtual keys contra el proveedor. Jabvox NO es proxy: la key se
# devuelve UNA sola vez al crearla y NUNCA se persiste; el cliente la usa directo contra el
# proveedor. Todo pasa por Jabvox::AiProvider::Client/BalanceService (nunca al proxy directo).
class Api::V1::Accounts::Jabvox::AiBudgetController < Api::V1::Accounts::Jabvox::BaseController
  # Gateado por el módulo de IA existente (no crea flags nuevos).
  jabvox_feature 'jabvox_ai_chat'
  include JabvoxPermissions

  before_action :ensure_admin

  # GET saldo de la cuenta (sin secretos). Refresca el gasto desde el proveedor si hay team.
  def show
    pa = provider_account
    Jabvox::AiProvider::BalanceService.new(Current.account).refresh_spend! if pa&.team_id_jabvox.present?
    render json: (pa&.reload&.summary || empty_summary)
  end

  # GET lista de virtual keys del team (metadatos, SIN la key en claro).
  def keys
    pa = provider_account
    return render json: { keys: [] } if pa.nil? || pa.team_id_jabvox.blank?

    resp = Jabvox::AiProvider::Client.new.list_keys(pa.team_id_jabvox)
    return render json: { error: resp.error }, status: :bad_gateway unless resp.success?

    render json: { keys: sanitize_keys(resp.data) }
  end

  # POST crea una virtual key del team. La key se devuelve UNA sola vez y no se guarda.
  def create_key # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
    pa = provider_account
    if pa.nil? || pa.team_id_jabvox.blank?
      return render json: { error: 'La cuenta aún no tiene saldo de IA aprovisionado.' }, status: :unprocessable_entity
    end

    max_usd = params[:max_budget_usd]
    error = budget_error(pa, max_usd)
    return render json: { error: error }, status: :unprocessable_entity if error

    resp = Jabvox::AiProvider::Client.new.generate_key(
      team_id: pa.team_id_jabvox,
      key_alias: params[:key_alias].presence || "cuenta-#{Current.account.id}-#{Time.current.to_i}",
      models: Array(params[:models]).map(&:to_s),
      max_budget_usd: max_usd.present? ? max_usd.to_f : nil,
      metadata: { 'crm_id' => Current.account.id.to_s }
    )
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

  # POST cambia el tope (max_budget) de una virtual key del team.
  def update_key
    max_usd = params[:max_budget_usd]
    return render json: { error: 'Indica un tope válido.' }, status: :unprocessable_entity if max_usd.blank?

    pa = provider_account
    error = pa && budget_error(pa, max_usd)
    return render json: { error: error }, status: :unprocessable_entity if error

    with_own_key { |token| Jabvox::AiProvider::Client.new.update_key(token, max_budget_usd: max_usd.to_f) }
  end

  private

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
      blocked: ActiveModel::Type::Boolean.new.cast(key['blocked']) || false }
  end
end
