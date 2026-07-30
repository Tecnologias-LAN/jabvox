module Jabvox::AccountWhatsappGroupsFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_whatsapp_groups_enabled_jabvox? if name.to_s == 'jabvox_whatsapp_groups'

    super
  end

  def enabled_features
    super.merge('jabvox_whatsapp_groups' => jabvox_whatsapp_groups_enabled_jabvox?)
  end
end
