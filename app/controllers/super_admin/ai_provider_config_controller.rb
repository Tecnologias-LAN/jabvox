# frozen_string_literal: true

# Pantalla del Super Admin para configurar el proveedor de API de IA: nombre, URL base,
# master key (cifrada, nunca precargada ni mostrada) y habilitado. Permite probar la conexión.
# rubocop:disable Rails/I18nLocaleTexts
class SuperAdmin::AiProviderConfigController < SuperAdmin::ApplicationController
  def show
    @config = JabvoxAiProviderConfig.instance
    @summary = @config.safe_summary
  end

  # Guarda la config. La master key en blanco = conservar la actual (nunca se sobreescribe con
  # vacío, y nunca se precarga en el HTML).
  def update # rubocop:disable Metrics/AbcSize
    config = JabvoxAiProviderConfig.instance
    attrs = {
      provider_name_jabvox: params[:provider_name].presence || config.provider_name_jabvox,
      base_url_jabvox: params[:base_url].to_s.strip.presence,
      enabled_jabvox: ActiveModel::Type::Boolean.new.cast(params[:enabled])
    }
    key = params[:master_key].to_s.strip
    attrs[:master_key_jabvox] = key if key.present?
    config.update!(attrs)
    redirect_to super_admin_ai_provider_config_path, notice: 'Configuración del proveedor guardada.'
  rescue StandardError => e
    Rails.logger.error("[AiProviderConfig] guardar: #{e.class}: #{e.message}")
    redirect_to super_admin_ai_provider_config_path, alert: 'No se pudo guardar la configuración.'
  end

  # Prueba la conexión contra el proveedor (consulta /model/info). Actualiza el estado.
  def test_connection
    config = JabvoxAiProviderConfig.instance
    return redirect_to super_admin_ai_provider_config_path, alert: 'Configura URL, master key y habilítalo antes de probar.' unless config.configured?

    resp = Jabvox::AiProvider::Client.new(config: config).models_info
    if resp.success?
      config.mark_connected!
      redirect_to super_admin_ai_provider_config_path, notice: 'Conexión exitosa con el proveedor.'
    else
      config.mark_error!(resp.error)
      redirect_to super_admin_ai_provider_config_path, alert: "El proveedor respondió con error: #{resp.error}"
    end
  rescue StandardError => e
    JabvoxAiProviderConfig.instance.mark_error!(e.message)
    redirect_to super_admin_ai_provider_config_path, alert: 'No se pudo conectar con el proveedor.'
  end
end
# rubocop:enable Rails/I18nLocaleTexts
