class Jabvox::AnalyzeAudioFileJob < ApplicationJob
  queue_as :low

  def perform(result_id)
    result = JabvoxAudioResult.find_by(id: result_id)
    return unless result
    return unless result.account.feature_enabled?('jabvox_audio_analysis')

    Jabvox::AudioAnalysisService.new(result).call
  end
end
