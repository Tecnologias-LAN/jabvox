# Impone una cuota por cuenta a un recurso Jabvox contable (reglas de automatización,
# dashboards de analytics, documentos de IA). Bloquea la CREACIÓN cuando la cuenta ya
# alcanzó el tope definido en account.usage_limits[<key>]. nil/ausente = ilimitado
# (usage_limits devuelve JabvoxApp.max_limit).
#
# Uso en el modelo:
#   include Jabvox::AccountResourceLimit
#   jabvox_resource_limit :automation_rules
#
# Para recursos repartidos en varios modelos (docs de IA = ai_chat + response_bot),
# se pasa `counts_with:` con los modelos que suman al total:
#   jabvox_resource_limit :ai_documents, counts_with: %w[JabvoxAiChatDocument JabvoxResponseBotDocument]
module Jabvox::AccountResourceLimit
  extend ActiveSupport::Concern

  class LimitExceeded < StandardError
    attr_reader :resource, :limit

    def initialize(resource, limit)
      @resource = resource
      @limit = limit
      super("Límite del paquete alcanzado para #{resource} (máximo #{limit}).")
    end
  end

  class_methods do
    # key: clave dentro de account.usage_limits (:automation_rules, :analytics_dashboards, :ai_documents)
    # counts_with: nombres de modelos que suman al conteo (por defecto, este mismo modelo)
    def jabvox_resource_limit(key, counts_with: nil)
      @jabvox_limit_key = key
      @jabvox_limit_models = Array(counts_with).presence
      before_create :ensure_within_jabvox_limit
    end

    attr_reader :jabvox_limit_key, :jabvox_limit_models
  end

  private

  def ensure_within_jabvox_limit
    key = self.class.jabvox_limit_key
    return if account.nil? || key.nil?

    limit = account.usage_limits[key].to_i
    return if limit <= 0 # 0 o ausente → sin tope efectivo (max_limit ya viene grande)

    raise LimitExceeded.new(key, limit) if jabvox_current_resource_count >= limit
  end

  # Cuenta los recursos existentes de la cuenta para esta clave. Si el límite abarca
  # varios modelos (docs de IA), suma el conteo de todos; si no, cuenta este modelo.
  def jabvox_current_resource_count
    models = self.class.jabvox_limit_models || [self.class.name]
    models.sum { |model_name| model_name.constantize.where(account_id: account_id).count }
  end
end
