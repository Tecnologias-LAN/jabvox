module Jabvox::AccountVoipFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_voip_enabled_jabvox? if name.to_s == 'jabvox_voip'

    super
  end

  def enabled_features
    super.merge('jabvox_voip' => jabvox_voip_enabled_jabvox?)
  end
end
