module Jabvox::AccountFormsFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_forms_enabled_jabvox? if name.to_s == 'jabvox_forms'

    super
  end

  def enabled_features
    super.merge('jabvox_forms' => jabvox_forms_enabled_jabvox?)
  end
end
