# frozen_string_literal: true

# Configuración del Widget de Soporte global (la burbuja "Soporte" del dashboard).
# Guarda el token del inbox de soporte y la clave HMAC en InstallationConfig, y
# ALINEA automáticamente el hmac_token de la bandeja de soporte con la clave HMAC
# global, para que la identificación del agente (setUser) valide correctamente.
#
#   GET  /super_admin/support_widget  → pantalla de configuración
#   POST /super_admin/support_widget  → guardar token + HMAC
class SuperAdmin::SupportWidgetController < SuperAdmin::ApplicationController
  def show
    load_config
  end

  def update
    token = params[:inbox_token].to_s.strip
    hmac = params[:hmac_key].to_s.strip

    if token.blank?
      redirect_to super_admin_support_widget_path, alert: token_required_msg
      return
    end

    persist_config(token, hmac)
    align_inbox_hmac(token)
    GlobalConfig.clear_cache if defined?(GlobalConfig)

    redirect_to super_admin_support_widget_path, notice: saved_msg
  rescue StandardError => e
    redirect_to super_admin_support_widget_path, alert: "No se pudo guardar: #{e.message}"
  end

  private

  def token_required_msg = 'El token del inbox es obligatorio.'
  def saved_msg = 'Widget de soporte guardado. Reinicia el servidor web para aplicar los cambios.'

  def load_config
    cfg = GlobalConfig.get('JABVOX_INBOX_TOKEN', 'JABVOX_INBOX_HMAC_KEY')
    @inbox_token = cfg['JABVOX_INBOX_TOKEN']
    @hmac_key = cfg['JABVOX_INBOX_HMAC_KEY']
    @support_inbox = resolve_support_inbox(@inbox_token)
    # ¿La clave HMAC global coincide con la de la bandeja? (necesario para el HMAC)
    @hmac_aligned = @support_inbox.present? &&
                    @hmac_key.present? &&
                    @support_inbox.channel.hmac_token == @hmac_key
    @enabled_accounts_count = Account.all.count { |a| a.feature_enabled?('contact_jabvox_support_team') }
  end

  def persist_config(token, hmac)
    InstallationConfig.find_or_initialize_by(name: 'JABVOX_INBOX_TOKEN').update!(value: token)
    # HMAC en blanco = conservar la clave actual; si no hay ninguna, usar la de la
    # bandeja. Nunca se sobreescribe con vacío.
    current = GlobalConfig.get('JABVOX_INBOX_HMAC_KEY')['JABVOX_INBOX_HMAC_KEY']
    effective_hmac = hmac.presence || current.presence || support_inbox_hmac(token)
    return if effective_hmac.blank?

    InstallationConfig.find_or_initialize_by(name: 'JABVOX_INBOX_HMAC_KEY').update!(value: effective_hmac)
  end

  # Alinea el hmac_token de la bandeja de soporte con la clave HMAC global, para
  # que el hash del agente (firmado con la global) valide en el widget (que valida
  # con el hmac_token de la bandeja). Sin esto, el HMAC siempre falla.
  def align_inbox_hmac(token)
    inbox = resolve_support_inbox(token)
    return if inbox.nil?

    global_hmac = GlobalConfig.get('JABVOX_INBOX_HMAC_KEY')['JABVOX_INBOX_HMAC_KEY']
    return if global_hmac.blank? || inbox.channel.hmac_token == global_hmac

    # update_column a propósito: solo tocamos el token, sin disparar las
    # validaciones/callbacks del channel (que no aplican a este ajuste puntual).
    inbox.channel.update_column(:hmac_token, global_hmac) # rubocop:disable Rails/SkipsModelValidations
  end

  def resolve_support_inbox(token)
    return nil if token.blank?

    channel = Channel::WebWidget.find_by(website_token: token)
    channel&.inbox
  end

  def support_inbox_hmac(token)
    resolve_support_inbox(token)&.channel&.hmac_token
  end
end
