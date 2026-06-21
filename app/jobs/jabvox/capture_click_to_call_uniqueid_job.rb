# Captures the Asterisk uniqueid for a click-to-call shortly after originate, independent of
# the Hangup event. Retries a few times because the agent channel takes a moment to appear in
# AMI Status. This makes the CDR↔typification link resilient even if Hangup never fires
# (e.g. the agent hangs up from MicroSIP and the event is missed).
class Jabvox::CaptureClickToCallUniqueidJob < ApplicationJob
  queue_as :high

  ATTEMPTS = 5
  INTERVAL = 2.seconds

  def perform(call_log_id, attempt = 1)
    call_log = JabvoxCallLog.find_by(id: call_log_id)
    return if call_log.nil? || call_log.uniqueid.present?

    config = call_log.account.jabvox_voip_config
    return if config&.host.blank?

    uniqueid = Jabvox::VoipService.new(config).channel_uniqueid(
      call_log_id: call_log.id, account_id: call_log.account_id
    )
    stamp_or_retry(call_log, uniqueid, attempt)
  end

  private

  def stamp_or_retry(call_log, uniqueid, attempt)
    if uniqueid.present?
      # update_columns: only stamping the link, no need to revalidate the record.
      call_log.update_columns(uniqueid: uniqueid) if call_log.reload.uniqueid.blank? # rubocop:disable Rails/SkipsModelValidations
    elsif attempt < ATTEMPTS
      self.class.set(wait: INTERVAL).perform_later(call_log.id, attempt + 1)
    end
  end
end
