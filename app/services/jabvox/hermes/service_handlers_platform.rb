# frozen_string_literal: true

# Handlers de los módulos de plataforma que faltaban en el catálogo de Hermes: saldo IA
# (LiteLLM), lista blanca de IP, horarios de atención, macros, equipos, agentes y etiquetas
# de conversación.
#
# Mismas reglas que el resto de handlers: actúan SIEMPRE sobre @account (nunca sobre un id
# que mande el LLM), NINGUNO borra, y las credenciales jamás salen en la respuesta.
#
# Largo a propósito, como ServiceHandlers: es el catálogo de un área funcional por sección y
# partirlo solo fragmentaría la whitelist.
# rubocop:disable Metrics/ModuleLength
module Jabvox::Hermes::ServiceHandlersPlatform
  # ==========================================================================
  # Saldo IA (LiteLLM)
  # ==========================================================================

  # Estado del saldo de IA de la cuenta: presupuesto del plan, saldo comprado, gasto y
  # disponible. Los importes se exponen en unidades monetarias además de centavos para que el
  # agente pueda responder sin convertir.
  def get_ai_balance(_params)
    pa = JabvoxAiProviderAccount.find_by(account_id: @account.id)
    return { configured: false, message: 'La cuenta no tiene saldo de IA configurado.' } if pa.nil?

    ai_balance_view(pa)
  end

  def ai_balance_view(provider_account)
    plan = provider_account.plan_budget_cents_jabvox.to_i
    purchased = provider_account.purchased_budget_cents_jabvox.to_i
    spend = (provider_account.cached_spend_jabvox.to_f * 100).round
    total = plan + purchased
    { configured: true, plan_budget_cents: plan, purchased_budget_cents: purchased,
      total_budget_cents: total, spend_cents: spend, available_cents: total - spend,
      total_budget: (total / 100.0).round(2), spend: (spend / 100.0).round(2),
      available: ((total - spend) / 100.0).round(2),
      status: provider_account.status_jabvox, period: provider_account.last_reset_period_jabvox,
      spend_updated_at: provider_account.spend_updated_at_jabvox, synced_at: provider_account.synced_at_jabvox }
  end

  # Movimientos del saldo (recargas, consumo de plan, ajustes) en un rango de fechas.
  def get_ai_balance_movements(params)
    scope = filter_by_date(JabvoxAiBalanceMovement.where(account_id: @account.id), params)
    scope = filter_by(scope, params, :kind_jabvox)
    scope.order(created_at: :desc).limit(capped_limit(params)).map do |m|
      { id: m.id, kind: m.kind_jabvox, amount_cents: m.amount_cents_jabvox,
        amount: (m.amount_cents_jabvox.to_i / 100.0).round(2),
        reference: m.reference_jabvox, created_at: m.created_at }
    end
  end

  # Fuerza la relectura del gasto contra el proveedor (LiteLLM). No mueve dinero.
  def refresh_ai_balance(_params)
    result = Jabvox::AiProvider::BalanceService.new(@account).refresh_spend!
    return { ok: false, error: 'No se pudo actualizar el gasto.' } unless result.respond_to?(:success?) && result.success?

    get_ai_balance({})
  end

  # Configuraciones de saldo del panel. NUNCA devuelve api_key/api_secret.
  def list_saldo_configs(params)
    JabvoxSaldoConfig.where(account_id: @account.id).order(:id).limit(capped_limit(params)).map do |c|
      { id: c.id, name: c.name_jabvox, base_url: c.base_url_jabvox, active: c.is_active_jabvox,
        cached_balance: c.cached_balance_jabvox, balance_updated_at: c.balance_updated_at_jabvox }
    end
  end

  # ==========================================================================
  # Lista blanca de IP
  # ==========================================================================

  def list_ip_whitelists(params)
    scope = filter_by(@account.jabvox_ip_whitelists, params, :is_active)
    scope.order(:id).limit(capped_limit(params)).map { |w| ip_whitelist_view(w) }
  end

  def create_ip_whitelist(params)
    w = @account.jabvox_ip_whitelists.new(params.slice(:ip, :comment).compact_blank)
    w.is_active = params.key?(:is_active) ? params[:is_active] : true
    w.created_by_id = @user&.id
    w.save!
    ip_whitelist_view(w)
  end

  # Editar, nunca borrar: desactivar es `is_active: false`.
  def update_ip_whitelist(params)
    w = @account.jabvox_ip_whitelists.find(params[:id])
    w.update!(params.slice(:ip, :comment, :is_active).compact)
    ip_whitelist_view(w)
  end

  def ip_whitelist_view(whitelist)
    { id: whitelist.id, ip: whitelist.ip, active: whitelist.is_active,
      comment: whitelist.comment, created_at: whitelist.created_at }
  end

  # ==========================================================================
  # Horarios de atención (por bandeja)
  # ==========================================================================

  DAY_NAMES = %w[domingo lunes martes miércoles jueves viernes sábado].freeze

  def get_working_hours(params)
    scope = @account.working_hours
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    scope.order(:inbox_id, :day_of_week).limit(capped_limit(params, default: 100)).map { |w| working_hour_view(w) }
  end

  # Actualiza el horario de UN día de una bandeja. El día es 0=domingo … 6=sábado.
  def update_working_hour(params)
    wh = @account.working_hours.find_by!(inbox_id: params[:inbox_id], day_of_week: params[:day_of_week])
    wh.update!(params.slice(:closed_all_day, :open_all_day, :open_hour, :open_minutes,
                            :close_hour, :close_minutes).compact)
    working_hour_view(wh)
  end

  def working_hour_view(hour)
    { id: hour.id, inbox_id: hour.inbox_id, day_of_week: hour.day_of_week,
      day_name: DAY_NAMES[hour.day_of_week.to_i],
      closed_all_day: hour.closed_all_day, open_all_day: hour.open_all_day,
      opens_at: format('%<h>02d:%<m>02d', h: hour.open_hour.to_i, m: hour.open_minutes.to_i),
      closes_at: format('%<h>02d:%<m>02d', h: hour.close_hour.to_i, m: hour.close_minutes.to_i) }
  end

  # ==========================================================================
  # Macros
  # ==========================================================================

  def list_macros(params)
    scope = filter_by(@account.macros, params, :visibility)
    scope.order(:id).limit(capped_limit(params)).map { |m| macro_view(m) }
  end

  def get_macro(params)
    macro_view(@account.macros.find(params[:id]), full: true)
  end

  def create_macro(params)
    m = @account.macros.new(name: params[:name], visibility: params[:visibility].presence || 'global')
    m.actions = params[:actions] if params[:actions].present?
    m.created_by_id = @user&.id
    m.updated_by_id = @user&.id
    m.save!
    macro_view(m, full: true)
  end

  def update_macro(params)
    m = @account.macros.find(params[:id])
    attrs = params.slice(:name, :visibility, :actions).compact
    m.updated_by_id = @user&.id
    m.update!(attrs)
    macro_view(m, full: true)
  end

  def macro_view(macro, full: false)
    base = { id: macro.id, name: macro.name, visibility: macro.visibility,
             actions_count: Array(macro.actions).size }
    full ? base.merge(actions: macro.actions) : base
  end

  # ==========================================================================
  # Equipos y agentes
  # ==========================================================================

  def list_teams(params)
    @account.teams.order(:id).limit(capped_limit(params)).map { |t| team_view(t) }
  end

  def get_team(params)
    team = @account.teams.find(params[:id])
    team_view(team).merge(
      members: team.members.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS)
                   .map { |u| { id: u.id, name: u.name, email: u.email } }
    )
  end

  def create_team(params)
    t = @account.teams.create!(params.slice(:name, :description, :allow_auto_assign).compact_blank)
    team_view(t)
  end

  def update_team(params)
    t = @account.teams.find(params[:id])
    t.update!(params.slice(:name, :description, :allow_auto_assign).compact)
    team_view(t)
  end

  def team_view(team)
    { id: team.id, name: team.name, description: team.description,
      allow_auto_assign: team.allow_auto_assign, members_count: team.members.size }
  end

  # Agentes de la cuenta con su rol y disponibilidad — para responder "quién puede atender
  # esto" o "a quién se lo asigno".
  def list_agents(params)
    scope = @account.account_users.includes(:user)
    scope = scope.where(role: params[:role]) if params[:role].present?
    scope.limit(capped_limit(params)).map do |au|
      { id: au.user_id, name: au.user&.name, email: au.user&.email,
        role: au.role, availability: au.availability, auto_offline: au.auto_offline }
    end
  end

  # ==========================================================================
  # Etiquetas de una conversación
  # ==========================================================================

  # Etiquetas puestas a una conversación, con desde cuándo las tiene (lo que permite
  # responder "cuánto lleva con esta etiqueta").
  def get_conversation_labels(params)
    conv = find_conversation!(params[:id])
    applied = ActsAsTaggableOn::Tagging.where(
      taggable_type: 'Conversation', taggable_id: conv.id, context: 'labels'
    ).includes(:tag)
    colors = @account.labels.pluck(:title, :color).to_h
    applied.map do |tagging|
      title = tagging.tag.name
      { title: title, color: colors[title],
        applied_at: tagging.created_at,
        days_applied: ((Time.current - tagging.created_at) / 1.day).floor }
    end
  end

  def add_conversation_label(params)
    conv = find_conversation!(params[:id])
    title = params[:label].to_s.strip
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'falta la etiqueta' if title.blank?

    conv.add_labels([title])
    { id: conv.display_id, labels: conv.reload.label_list }
  end

  # Quitar una etiqueta NO es borrar un registro de negocio: es despegar una marca de la
  # conversación, así que sí está permitido (la etiqueta sigue existiendo en la cuenta).
  def remove_conversation_label(params)
    conv = find_conversation!(params[:id])
    title = params[:label].to_s.strip
    conv.label_list.remove(title)
    conv.save!
    { id: conv.display_id, labels: conv.reload.label_list }
  end

  # Acepta el display_id (el número que ve el humano), como el resto de tools de conversación.
  def find_conversation!(raw_id)
    @account.conversations.find_by!(display_id: raw_id)
  end
end
# rubocop:enable Metrics/ModuleLength
