module Jabvox::AccountWhatsappTemplatesFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_whatsapp_templates_enabled_jabvox? if name.to_s == 'jabvox_whatsapp_templates'

    super
  end

  def enabled_features
    super.merge('jabvox_whatsapp_templates' => jabvox_whatsapp_templates_enabled_jabvox?)
  end
end
