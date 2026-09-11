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
  def create_key # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    pa = provider_account
    if pa.nil? || pa.team_id_jabvox.blank?
      return render json: { error: 'La cuenta aún no tiene saldo de IA aprovisionado.' }, status: :unprocessable_entity
    end

    max_usd = params[:max_budget_usd]
    if max_usd.present? && max_usd.to_f > pa.total_budget_usd
      return render json: { error: "El tope de la key (#{max_usd}) excede el saldo del team (#{pa.total_budget_usd})." },
                    status: :unprocessable_entity
    end

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

  private

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

  # Nunca devuelve la key en claro (el proveedor tampoco la devuelve en /key/list): solo metadatos.
  def sanitize_keys(data)
    list = data.is_a?(Hash) ? (data['keys'] || data['data'] || []) : Array(data)
    Array(list).map do |k|
      k = k.is_a?(Hash) ? k : {}
      { alias: k['key_alias'], token_id: k['token_id'] || k['token'],
        spend: k['spend'], max_budget: k['max_budget'], blocked: k['blocked'] }
    end
  end
end
