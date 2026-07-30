module Jabvox::AccountVoiceBroadcastFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_voice_broadcast_enabled_jabvox? if name.to_s == 'jabvox_voice_broadcast'

    super
  end

  def enabled_features
    super.merge('jabvox_voice_broadcast' => jabvox_voice_broadcast_enabled_jabvox?)
  end
end
