# When an account gets BOTH the CDR and Audio Analysis modules enabled, the
# pipelines from each module are backfilled into the other so both sides start
# with the same set (and stay mirrored from then on via the pipeline models'
# after_commit callbacks).
#
# This fires specifically on the transition into "both enabled": i.e. when one
# of the two flags flips to true and the other was already on. Runs the sync in
# a background job so toggling a feature from Super Admin stays fast and a sync
# hiccup never blocks the account update.
module Jabvox::AccountPipelineSync
  extend ActiveSupport::Concern

  included do
    after_update_commit :backfill_pipelines_when_both_enabled
  end

  private

  def backfill_pipelines_when_both_enabled
    flag_changed = saved_change_to_jabvox_cdr_enabled_jabvox? ||
                   saved_change_to_jabvox_audio_analysis_enabled_jabvox?
    return unless flag_changed
    return unless jabvox_cdr_enabled_jabvox? && jabvox_audio_analysis_enabled_jabvox?

    Jabvox::PipelineBackfillJob.perform_later(id)
  end
end
