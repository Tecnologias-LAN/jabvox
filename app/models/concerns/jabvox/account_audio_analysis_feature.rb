module Jabvox::AccountAudioAnalysisFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_audio_analysis_enabled_jabvox? if name.to_s == 'jabvox_audio_analysis'

    super
  end

  def enabled_features
    super.merge('jabvox_audio_analysis' => jabvox_audio_analysis_enabled_jabvox?)
  end
end
