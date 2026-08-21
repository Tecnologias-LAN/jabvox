# Aprovisiona una cuenta completa a partir de un pago (auto-provisioning desde n8n):
# crea la cuenta + su usuario administrador, activa los módulos Jabvox indicados y
# fija los límites por recurso. Todo en una transacción: si algo falla, no queda una
# cuenta a medias.
#
# NO define "paquetes": la web envía los recursos concretos (nº de bandejas, usuarios,
# reglas, dashboards, docs de IA, formularios) y la lista de módulos a activar.
#
# Entrada (todo opcional salvo email):
#   email:            del comprador (será el admin)
#   name:             nombre de la cuenta (default: derivado del email)
#   admin_name:       nombre del usuario admin
#   password:         contraseña inicial (si no viene, se genera una aleatoria)
#   locale:           idioma de la cuenta (default 'es')
#   modules:          ['tickets','kanban',...] nombres cortos de módulos Jabvox a activar
#   limits:           { inboxes:, agents:, ai_documents:, automation_rules:,
#                       analytics_dashboards:, forms:, advanced_flows: }
#   idempotency_key:  clave única del pago (p.ej. id de la sesión de Stripe). Si se
#                     repite, NO se crea otra cuenta: se devuelve la existente. Permite
#                     reintentos seguros desde n8n ("si falla un nodo, vuelve y empieza").
#
# Salida: { account:, user:, created_user:, limits:, modules:, features:,
#           set_password_url:, replayed? } — created_user indica si el admin se creó
# nuevo; replayed:true aparece solo cuando fue un reintento (cuenta ya existente).
class Jabvox::AccountProvisioningService
  class ProvisioningError < StandardError; end

  # Límites que van directo a accounts.limits (jsonb) con su clave allí.
  #   entrada del payload  =>  clave en accounts.limits
  ACCOUNT_LIMIT_MAP = {
    inboxes: 'inboxes',
    agents: 'agents',
    ai_documents: 'ai_documents',
    automation_rules: 'automation_rules',
    analytics_dashboards: 'analytics_dashboards',
    email_templates: 'email_templates',
    storage_gb: 'storage_gb'
  }.freeze

  # Clave donde se guarda la huella de idempotencia dentro de accounts.custom_attributes.
  IDEMPOTENCY_ATTR = 'provisioning_idempotency_key'.freeze

  def initialize(params = {})
    @params = params.symbolize_keys
    @email = @params[:email].to_s.strip.downcase
    @modules = Array(@params[:modules]).map(&:to_s)
    @features = Array(@params[:features]).map(&:to_s) # features nativas de Chatwoot
    @limits = (@params[:limits] || {}).symbolize_keys
    @base_url = @params[:base_url].presence # para armar el link de set-password
    @idempotency_key = @params[:idempotency_key].to_s.strip.presence
    # Flujo "registro primero": la cuenta+admin YA existen (creados en el registro).
    # Cuando llega account_id, aprovisionamos SOBRE esa cuenta en vez de crear una nueva.
    @account_id = @params[:account_id].presence
  end

  def call
    validate!

    # Reintento seguro: si esta idempotency_key ya aprovisionó una cuenta, la devolvemos
    # tal cual (idempotente) en vez de crear una duplicada. Así n8n puede "volver y
    # empezar" sin efectos secundarios.
    existing = find_by_idempotency_key
    return replay_result(existing) if existing

    ActiveRecord::Base.transaction do
      @account, @user, @created_user = resolve_account_and_admin
      link_admin!
      apply_modules!
      apply_chatwoot_features!
      apply_form_limit!
      apply_advanced_flows_limit!
    end

    # Token de establecer-contraseña (fuera de la transacción: escribe en users).
    @set_password_url = build_set_password_url
    result
  end

  private

  # Columnas válidas de módulos, derivadas del catálogo del super admin (fuente única).
  def module_columns
    @module_columns ||= JabvoxModulesField::MODULES.to_h do |column, _label|
      short = column.to_s.delete_prefix('jabvox_').delete_suffix('_enabled_jabvox')
      [short, column.to_s]
    end
  end

  def validate!
    raise ProvisioningError, 'email es obligatorio' if @email.blank?
    raise ProvisioningError, 'email inválido' unless @email.match?(URI::MailTo::EMAIL_REGEXP)

    unknown = @modules.reject { |m| module_columns.key?(m) }
    raise ProvisioningError, "módulos desconocidos: #{unknown.join(', ')}" if unknown.any?

    unknown_features = @features - available_chatwoot_features
    raise ProvisioningError, "features desconocidas: #{unknown_features.join(', ')}" if unknown_features.any?
  end

  # Nombres válidos de features nativas de Chatwoot (Featurable ya carga features.yml).
  def available_chatwoot_features
    @available_chatwoot_features ||= Account::FEATURE_LIST.filter_map { |f| f['name'] }
  end

  # Decide sobre qué cuenta+admin aprovisionar:
  #   - Flujo "registro primero" (account_id presente): usa la cuenta y su admin YA creados
  #     en el registro; solo actualiza límites y marca la idempotency_key.
  #   - Flujo clásico (n8n, sin account_id): crea la cuenta y busca/crea el admin por email.
  # Devuelve [account, user, created_user].
  def resolve_account_and_admin
    if @account_id
      account = use_existing_account
      user = account.administrators.first || account.users.first
      [account, user, false]
    else
      account = build_account
      user, created = find_or_create_admin
      [account, user, created]
    end
  end

  # Aprovisiona sobre la cuenta existente (creada en el registro): aplica límites y deja
  # la huella de idempotencia. NO cambia el status aquí (lo hace apply_plan_period! del
  # billing tras confirmar el pago).
  def use_existing_account
    account = Account.find(@account_id)
    attrs = { limits: account.limits.to_h.merge(account_limits) }
    if @idempotency_key
      attrs[:custom_attributes] = account.custom_attributes.to_h.merge(IDEMPOTENCY_ATTR => @idempotency_key)
    end
    account.update!(attrs)
    account
  end

  # Crea la cuenta con sus límites de accounts.limits ya puestos (enforcement inmediato
  # para inboxes/agents/ai_documents/automation_rules/analytics_dashboards).
  def build_account
    attrs = { name: account_name, locale: locale, limits: account_limits, status: :payment_pending }
    attrs[:custom_attributes] = { IDEMPOTENCY_ATTR => @idempotency_key } if @idempotency_key
    Account.create!(attrs)
  end

  # Busca una cuenta ya aprovisionada con la misma idempotency_key (reintento de n8n).
  def find_by_idempotency_key
    return if @idempotency_key.blank?

    Account.where('custom_attributes ->> ? = ?', IDEMPOTENCY_ATTR, @idempotency_key).first
  end

  # Rearma la respuesta a partir de la cuenta ya existente, SIN volver a tocar nada
  # ni generar un nuevo token de contraseña (el admin ya la habrá establecido).
  def replay_result(account)
    @account = account
    @user = account.administrators.first || account.users.first
    @created_user = false
    @set_password_url = nil # ya se envió en el primer intento; no se regenera
    result.merge(replayed: true)
  end

  def account_name
    @account_name ||= @params[:name].presence || default_account_name
  end

  def locale
    @params[:locale].presence || 'es'
  end

  # Construye el hash accounts.limits solo con las claves presentes y numéricas.
  def account_limits
    ACCOUNT_LIMIT_MAP.each_with_object({}) do |(param_key, limit_key), acc|
      value = @limits[param_key]
      acc[limit_key] = value.to_i if value.present? && value.to_i.positive?
      copy_billable_metadata(param_key, acc)
    end.tap do |acc|
      %i[forms advanced_flows].each do |param_key|
        value = @limits[param_key]
        acc[param_key.to_s] = value.to_i if value.present? && value.to_i.positive?
        copy_billable_metadata(param_key, acc)
      end
    end
  end

  def copy_billable_metadata(param_key, acc)
    %w[included extra unit_price_cents].each do |suffix|
      key = "#{param_key}_#{suffix}"
      value = @limits[key.to_sym] || @limits[key]
      acc[key] = value.to_i if value.present? && value.to_i.positive?
    end
  end

  def find_or_create_admin
    existing = User.from_email(@email)
    return [existing, false] if existing

    user = User.new(name: admin_name, email: @email, password: initial_password)
    user.skip_confirmation!
    user.save!
    [user, true]
  end

  def link_admin!
    return if @user.nil? # cuenta existente sin usuarios: nada que vincular

    au = @account.account_users.find_or_initialize_by(user_id: @user.id)
    au.update!(role: :administrator)
  end

  # Activa las columnas jabvox_*_enabled_jabvox de los módulos pedidos (una sola escritura).
  def apply_modules!
    return if @modules.empty?

    updates = @modules.index_with { true }.transform_keys { |m| module_columns[m] }
    @account.update!(updates)
  end

  # Activa las features NATIVAS de Chatwoot (crm, help_center, campaigns, agent_bots…).
  def apply_chatwoot_features!
    return if @features.empty?

    @account.enable_features!(*@features)
  end

  # Formularios: el tope vive en jabvox_form_configs.max_forms_jabvox (setter en Account).
  def apply_form_limit!
    forms = @limits[:forms]
    return if forms.blank? || forms.to_i <= 0

    @account.max_forms_jabvox = forms.to_i
  end

  # Automatización avanzada: el tope de flujos vive en account_automation_config.max_flows.
  # Solo se guarda el número; el aprovisionamiento remoto de la plataforma Automations
  # (que además valida el flag) lo maneja Automations::AccountProvisioner aparte.
  def apply_advanced_flows_limit!
    flows = @limits[:advanced_flows]
    return if flows.blank? || flows.to_i <= 0

    config = @account.account_automation_config || @account.build_account_automation_config
    config.max_flows = flows.to_i
    config.save!(validate: false)
  end

  def admin_name
    @params[:admin_name].presence || account_name
  end

  # Contraseña temporal (el admin la reemplaza con el link de set-password). Debe
  # cumplir la política: minúscula, mayúscula, dígito y carácter especial.
  def initial_password
    @params[:password].presence || generate_strong_password
  end

  def generate_strong_password
    "#{SecureRandom.alphanumeric(18)}Aa1!"
  end

  def default_account_name
    @email.split('@').first.to_s.tr('._-', ' ').strip.presence || 'Cuenta Jabvox'
  end

  # Link seguro y temporal para que el admin ESTABLEZCA su contraseña (token Devise).
  # No se envía contraseña por correo; el correo (desde n8n) usa este enlace.
  def build_set_password_url
    raw_token = @user.send(:set_reset_password_token)
    base = (@base_url.presence || ENV.fetch('FRONTEND_URL', 'https://app.jabvox.com')).delete_suffix('/')
    "#{base}/app/auth/password/edit?reset_password_token=#{raw_token}"
  end

  def result
    {
      account: @account,
      user: @user,
      created_user: @created_user,
      limits: @account.reload.limits,
      modules: @modules,
      features: @features,
      set_password_url: @set_password_url
    }
  end
end
