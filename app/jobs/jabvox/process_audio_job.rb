class Jabvox::ProcessAudioJob < ApplicationJob
  queue_as :low

  # Fans out one AnalyzeAudioFileJob per pending result, so files are processed
  # in parallel and each one is independently retryable.
  def perform(audio_job_id)
    job = JabvoxAudioJob.find_by(id: audio_job_id)
    return unless job
    return unless job.account.feature_enabled?('jabvox_audio_analysis')

    job.update!(status: 'processing')
    job.results.where(status: 'pending').find_each do |result|
      Jabvox::AnalyzeAudioFileJob.perform_later(result.id)
    end
  end
end
