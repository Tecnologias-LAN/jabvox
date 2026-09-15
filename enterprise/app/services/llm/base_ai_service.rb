# frozen_string_literal: true

# Base service for LLM operations using RubyLLM.
# New features should inherit from this class.
class Llm::BaseAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_TEMPERATURE = 1.0

  attr_reader :model, :temperature

  def initialize(feature: nil, account: nil, fallback_model: nil)
    @llm_feature = feature
    @llm_account = account
    @fallback_model = fallback_model

    Llm::Config.initialize!
    @jabvox_ia = jabvox_ia_settings # credenciales/modelo propios de la cuenta (si los hay)
    setup_model
    setup_temperature
  end

  # Si la cuenta conectó Jabvox IA, el chat usa SUS credenciales (base_url + api_key) y su
  # modelo — así cada cuenta usa su propio proveedor/modelo (LiteLLM, deepseek, etc.). Si no,
  # cae a la configuración global (comportamiento anterior).
  def chat(model: @model, temperature: @temperature)
    if @jabvox_ia
      Llm::Config.with_api_key(@jabvox_ia[:api_key], api_base: @jabvox_ia[:api_base]) do |context|
        context.chat(model: model).with_temperature(temperature)
      end
    else
      RubyLLM.chat(model: model).with_temperature(temperature)
    end
  end

  private

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def setup_model
    # El modelo de Jabvox IA de la cuenta tiene prioridad (cada cuenta su modelo).
    return @model = @jabvox_ia[:model] if @jabvox_ia && @jabvox_ia[:model].present?

    route = feature_route
    return @model = route[:model] if account_override_route?(route)

    @model = @fallback_model.presence || installation_model.presence || route&.dig(:model) || DEFAULT_MODEL
  end

  # Lee las credenciales/modelo del hook Jabvox IA de la cuenta (si está conectado y
  # habilitado). Devuelve { api_key:, api_base:, model: } o nil.
  def jabvox_ia_settings
    return nil if @llm_account.nil?

    hook = @llm_account.hooks.find_by(app_id: 'jabvox_ia', status: :enabled)
    return nil if hook.nil?

    api_key = hook.settings&.dig('api_key').presence
    return nil if api_key.blank?

    { api_key: api_key,
      api_base: hook.settings&.dig('base_url').presence,
      model: hook.settings&.dig('model').presence }
  rescue StandardError => e
    Rails.logger.error("[jabvox_ia] no se pudieron leer credenciales del hook | #{e.message}")
    nil
  end

  def feature_route
    return if @llm_feature.blank?

    Llm::FeatureRouter.resolve(feature: @llm_feature, account: @llm_account)
  end

  def account_override_route?(route)
    route&.dig(:source) == :account_override
  end

  def installation_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
  end

  def setup_temperature
    @temperature = DEFAULT_TEMPERATURE
  end
end
