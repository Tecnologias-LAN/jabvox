module Jabvox::AccountSoftphoneFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_softphone_enabled_jabvox? if name.to_s == 'jabvox_softphone'

    super
  end

  def enabled_features
    super.merge('jabvox_softphone' => jabvox_softphone_enabled_jabvox?)
  end
end
