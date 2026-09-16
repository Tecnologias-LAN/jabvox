module Jabvox::AccountWhatsappFlowsFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_whatsapp_flows_enabled_jabvox? if name.to_s == 'jabvox_whatsapp_flows'

    super
  end

  def enabled_features
    super.merge('jabvox_whatsapp_flows' => jabvox_whatsapp_flows_enabled_jabvox?)
  end
end
