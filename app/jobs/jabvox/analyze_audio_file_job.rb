class Jabvox::AnalyzeAudioFileJob < ApplicationJob
  include Jabvox::AccountFairShare
  queue_as :jabvox_media

  # Máximo de audios EN VUELO por cuenta (fairness): una cuenta con miles de audios no
  # acapara los slots del worker media ni ahoga a las demás. Override por ENV.
  fair_share_limit 10
  fair_share_env 'JABVOX_AUDIO_MAX_INFLIGHT_PER_ACCOUNT'

  def perform(result_id)
    result = JabvoxAudioResult.find_by(id: result_id)
    return unless result
    return unless result.account.feature_enabled?('jabvox_audio_analysis')
    # Idempotencia: si ya se completó (reintento solapado), no re-gastar la IA externa.
    return if result.respond_to?(:status) && result.status.to_s == 'completed'

    with_account_fair_share(result.account_id) do
      Jabvox::AudioAnalysisService.new(result).call
    end
  end
end
