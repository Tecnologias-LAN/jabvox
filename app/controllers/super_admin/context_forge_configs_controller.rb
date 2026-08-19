# frozen_string_literal: true

# Configuración GLOBAL del gateway ContextForge (IBM MCP Gateway) desde el super admin.
# Clona el patrón de AutomationsConfigsController: valores en InstallationConfig, secretos
# enmascarados (blanco = conservar), y una prueba de conexión autenticada.
#
# ContextForge + el servidor MCP backend viven FUERA de Jabvox. Aquí solo se guarda cómo
# alcanzarlos (base_url + admin key maestra) para que el Provisioner cree, por cuenta,
# team → Hermes → MCPs → virtual server → scoped token.
class SuperAdmin::ContextForgeConfigsController < SuperAdmin::ApplicationController
  ALLOWED_CONFIGS = %w[
    CONTEXTFORGE_SERVICE_URL
    CONTEXTFORGE_ADMIN_KEY
    CONTEXTFORGE_HERMES_URL
    CONTEXTFORGE_JABVOX_CALLBACK_URL
  ].freeze

  # Secretos que nunca se re-renderizan: un envío en blanco = "conservar el valor actual".
  MASKED_SECRETS = %w[CONTEXTFORGE_ADMIN_KEY].freeze

  URL_CONFIGS = {
    'CONTEXTFORGE_SERVICE_URL' => 'ContextForge Service URL',
    'CONTEXTFORGE_HERMES_URL' => 'Hermes Gateway URL',
    'CONTEXTFORGE_JABVOX_CALLBACK_URL' => 'Jabvox Callback URL'
  }.freeze

  before_action :load_app_config

  def show; end

  def create
    errors = url_errors
    errors = persist_configs! if errors.empty?

    if errors.any?
      redirect_to super_admin_context_forge_config_path, alert: errors.join(', ')
    else
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_context_forge_config_path, notice: 'Configuración de ContextForge actualizada'
      # rubocop:enable Rails/I18nLocaleTexts
    end
  end

  # Prueba de conexión autenticada contra ContextForge (verifica base_url + admin key).
  def health
    @health = ContextForge::Service.new.verify_global_config
    render :show
  end

  private

  def persist_configs!
    errors = []
    (params['app_config'] || {}).each do |key, value|
      next unless ALLOWED_CONFIGS.include?(key)
      next if skip_blank_secret?(key, value)

      i = InstallationConfig.where(name: key).first_or_create(value: value, locked: false)
      i.value = value
      errors.concat(i.errors.full_messages) unless i.save
    end
    errors
  end

  def url_errors
    submitted = params['app_config'] || {}
    URL_CONFIGS.filter_map do |key, label|
      next unless submitted.key?(key)

      Automations::UrlValidator.url_error(submitted[key], label)
    end
  end

  # rubocop:disable Style/HashTransformValues
  def load_app_config
    @app_config = InstallationConfig.where(name: ALLOWED_CONFIGS)
                                    .pluck(:name, :serialized_value)
                                    .map { |name, serialized_value| [name, serialized_value['value']] }
                                    .to_h
  end
  # rubocop:enable Style/HashTransformValues

  def skip_blank_secret?(key, value)
    MASKED_SECRETS.include?(key) && value.blank?
  end
end
