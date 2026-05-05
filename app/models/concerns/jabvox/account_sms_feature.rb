module Jabvox::AccountSmsFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_sms_enabled_jabvox? if name.to_s == 'jabvox_sms'

    super
  end

  def enabled_features
    super.merge('jabvox_sms' => jabvox_sms_enabled_jabvox?)
  end
end
