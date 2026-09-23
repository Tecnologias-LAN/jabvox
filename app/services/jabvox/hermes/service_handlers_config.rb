# frozen_string_literal: true

# Handlers de configuración y catálogos: tipificaciones, monedas, unidades de medida,
# visibilidad de campos, extensiones de agente, y la configuración de SMTP / VoIP / SMS.
#
# Reglas, iguales al resto: todo bajo @account, NINGUNO borra y las CREDENCIALES nunca salen
# en la respuesta. Las configuraciones de SMTP, VoIP y proveedores SMS guardan contraseñas,
# así que se exponen con un booleano `has_password` en vez del valor.
#
module Jabvox::Hermes::ServiceHandlersConfig
  # ==========================================================================
  # Tipificaciones
  # ==========================================================================

  def list_typifications(params)
    scope = filter_by(@account.jabvox_typifications, params, :is_active)
    scope.order(:id).limit(capped_limit(params)).map { |t| typification_view(t) }
  end

  def create_typification(params)
    t = @account.jabvox_typifications.new(params.slice(:name, :description).compact_blank)
    t.is_active = params.key?(:is_active) ? params[:is_active] : true
    t.created_by_id = @user&.id
    t.save!
    typification_view(t)
  end

  def update_typification(params)
    t = @account.jabvox_typifications.find(params[:id])
    t.update!(params.slice(:name, :description, :is_active).compact)
    typification_view(t)
  end

  def typification_view(typification)
    { id: typification.id, name: typification.name, description: typification.description,
      active: typification.is_active }
  end

  # ==========================================================================
  # Monedas y unidades de medida
  # ==========================================================================

  def list_currencies(params)
    scope = filter_by(@account.jabvox_currencies, params, :active_jabvox)
    scope.order(:id).limit(capped_limit(params)).map { |c| currency_view(c) }
  end

  def currency_view(currency)
    { id: currency.id, name: currency.name_jabvox, symbol: currency.symbol_jabvox,
      active: currency.active_jabvox }
  end

  def list_units_of_measure(params)
    scope = filter_by(@account.jabvox_units_of_measure, params, :active_jabvox)
    scope.order(:id).limit(capped_limit(params)).map { |u| unit_view(u) }
  end

  def unit_view(unit)
    { id: unit.id, name: unit.name_jabvox, abbreviation: unit.abbreviation_jabvox, active: unit.active_jabvox }
  end

  # ==========================================================================
  # Visibilidad de campos y extensiones de agente
  # ==========================================================================

  def list_field_visibilities(params)
    scope = filter_by(@account.jabvox_field_visibilities, params, :user_id, :field_name)
    scope.order(:id).limit(capped_limit(params)).map do |f|
      { id: f.id, user_id: f.user_id, field_name: f.field_name, can_view: f.can_view }
    end
  end

  def update_field_visibility(params)
    f = @account.jabvox_field_visibilities.find_or_initialize_by(
      user_id: params[:user_id], field_name: params[:field_name].to_s
    )
    f.can_view = params[:can_view]
    f.save!
    { id: f.id, user_id: f.user_id, field_name: f.field_name, can_view: f.can_view }
  end

  # Extensión SIP de cada agente — para saber a qué extensión marcar.
  def list_user_extensions(params)
    scope = filter_by(@account.jabvox_user_extensions.includes(:user), params, :user_id)
    scope.order(:id).limit(capped_limit(params)).map do |e|
      { id: e.id, user_id: e.user_id, user_name: e.try(:user)&.name, extension: e.extension_jabvox }
    end
  end

  def update_user_extension(params)
    e = @account.jabvox_user_extensions.find_or_initialize_by(user_id: params[:user_id])
    e.extension_jabvox = params[:extension].to_s
    e.save!
    { id: e.id, user_id: e.user_id, extension: e.extension_jabvox }
  end

  # ==========================================================================
  # Configuración de canales (SMTP / VoIP / proveedores SMS)
  #
  # Todas guardan contraseñas: se devuelve `has_password`, NUNCA el valor.
  # ==========================================================================

  def get_smtp_config(_params)
    c = @account.jabvox_smtp_config
    return { configured: false } if c.nil?

    { configured: true, id: c.id, from_name: c.from_name, from_email: c.from_email,
      address: c.address, port: c.port, domain: c.domain, username: c.username,
      has_password: c.password.present?, authentication: c.authentication,
      starttls: c.enable_starttls_auto, ssl_tls: c.enable_ssl_tls, verified: c.verified,
      calendar_reminders_enabled: c.calendar_reminders_enabled,
      calendar_reminder_minutes: c.calendar_reminder_minutes }
  end

  def get_voip_config(_params)
    c = @account.jabvox_voip_config
    return { configured: false } if c.nil?

    { configured: true, id: c.id, host: c.host, port: c.port, username: c.username,
      has_password: c.password.present?, context: c.context, dialer_context: c.dialer_context,
      dialer_trunk: c.dialer_trunk, dialer_caller_id: c.dialer_caller_id,
      dial_field: c.dial_field_jabvox, dial_prefix: c.dial_prefix_jabvox,
      dialer_provider_prefix: c.dialer_provider_prefix }
  end

  def list_sms_providers(params)
    scope = filter_by(@account.jabvox_sms_providers, params, :active)
    scope.order(:id).limit(capped_limit(params)).map do |p|
      { id: p.id, name: p.name, base_url: p.base_url, api_user: p.api_user,
        has_password: p.api_password.present?, active: p.active }
    end
  end

  # Mensajes SMS enviados, con filtros por campaña, estado y fecha.
  def list_sms_messages(params)
    scope = filter_by(@account.jabvox_sms_messages, params, :jabvox_sms_campaign_id, :status, :contact_id)
    scope = filter_by_date(scope, params)
    scope.order(created_at: :desc).limit(capped_limit(params)).map do |m|
      { id: m.id, campaign_id: m.jabvox_sms_campaign_id, contact_id: m.contact_id,
        phone: m.phone, status: m.status, error: m.error_message,
        sent_at: m.sent_at, created_at: m.created_at }
    end
  end
end
