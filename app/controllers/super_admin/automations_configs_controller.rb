class SuperAdmin::AutomationsConfigsController < SuperAdmin::ApplicationController
  ALLOWED_CONFIGS = %w[AUTOMATIONS_SERVICE_URL AUTOMATIONS_PROVISION_KEY].freeze

  before_action :load_app_config

  def show; end

  def create
    errors = []
    (params['app_config'] || {}).each do |key, value|
      next unless ALLOWED_CONFIGS.include?(key)
      next if skip_blank_secret?(key, value)

      i = InstallationConfig.where(name: key).first_or_create(value: value, locked: false)
      i.value = value
      errors.concat(i.errors.full_messages) unless i.save
    end

    if errors.any?
      redirect_to super_admin_automations_config_path, alert: errors.join(', ')
    else
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_automations_config_path, notice: 'Configuración de Automations actualizada'
      # rubocop:enable Rails/I18nLocaleTexts
    end
  end

  # Probes the public /health endpoint of the Automations service and shows the result.
  def health
    @health = Automations::ProvisioningService.new.service_health
    render :show
  end

  private

  # ref: https://github.com/rubocop/rubocop/issues/7767
  # rubocop:disable Style/HashTransformValues
  def load_app_config
    @app_config = InstallationConfig.where(name: ALLOWED_CONFIGS)
                                    .pluck(:name, :serialized_value)
                                    .map { |name, serialized_value| [name, serialized_value['value']] }
                                    .to_h
  end
  # rubocop:enable Style/HashTransformValues

  # The master provisioning key is never re-rendered, so a blank submission
  # means "keep the current value" rather than "clear it".
  def skip_blank_secret?(key, value)
    key == 'AUTOMATIONS_PROVISION_KEY' && value.blank?
  end
end
