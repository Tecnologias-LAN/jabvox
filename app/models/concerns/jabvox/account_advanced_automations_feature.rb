module Jabvox::AccountAdvancedAutomationsFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_advanced_automations_enabled_jabvox? if name.to_s == 'jabvox_advanced_automations'

    super
  end

  def enabled_features
    super.merge('jabvox_advanced_automations' => jabvox_advanced_automations_enabled_jabvox?)
  end
end
