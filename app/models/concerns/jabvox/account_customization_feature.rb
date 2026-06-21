module Jabvox::AccountCustomizationFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_customization_enabled_jabvox? if name.to_s == 'jabvox_customization'

    super
  end

  def enabled_features
    super.merge('jabvox_customization' => jabvox_customization_enabled_jabvox?)
  end
end
