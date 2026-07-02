# When an account gets BOTH the Audio Analysis and AI Chat modules enabled, the
# storages from each module are backfilled into the other so both sides start
# with the same set (and stay mirrored from then on via the storage models'
# after_commit callbacks).
#
# Mirrors Jabvox::AccountPipelineSync. Fires on the transition into "both
# enabled" and runs the sync in a background job.
module Jabvox::AccountStorageSync
  extend ActiveSupport::Concern

  included do
    after_update_commit :backfill_storages_when_both_enabled
  end

  private

  def backfill_storages_when_both_enabled
    flag_changed = saved_change_to_jabvox_ai_chat_enabled_jabvox? ||
                   saved_change_to_jabvox_audio_analysis_enabled_jabvox?
    return unless flag_changed
    return unless jabvox_ai_chat_enabled_jabvox? && jabvox_audio_analysis_enabled_jabvox?

    Jabvox::StorageBackfillJob.perform_later(id)
  end
end
