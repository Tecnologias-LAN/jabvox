# Handles the end of a click-to-call: stamps the recording uniqueid on the call
# log and notifies the agent over ActionCable so the typify dialog opens.
class Jabvox::ClickToCallHangupService
  def initialize(account_id, call_log_id, uniqueid)
    @account_id = account_id
    @call_log_id = call_log_id
    @uniqueid = uniqueid
  end

  def call
    call_log = JabvoxCallLog.find_by(id: @call_log_id, account_id: @account_id)
    return unless call_log

    # Stamp the uniqueid whenever it's still missing — even if the agent already typified
    # (race: typify PATCH can land before this Hangup event). Never overwrite a good value
    # with nil, and never blank an existing one.
    call_log.update_columns(uniqueid: @uniqueid) if @uniqueid.present? && call_log.uniqueid.blank? # rubocop:disable Rails/SkipsModelValidations

    # Move to 'ended' only if the call was still ringing/active; don't regress 'typified'.
    call_log.update_columns(status: 'ended') if call_log.status == 'calling' # rubocop:disable Rails/SkipsModelValidations

    broadcast(call_log.reload)
  end

  private

  def broadcast(call_log)
    token = call_log.user&.pubsub_token
    return if token.blank?

    # account_id is REQUIRED: the frontend ActionCable connector drops any event
    # whose data.account_id doesn't match the current account (isAValidEvent).
    # Without it the 'jabvox.call.ended' event was silently discarded, so the
    # typify dialog never opened when the customer/MicroSIP hung up.
    ActionCable.server.broadcast(
      token,
      {
        event: 'jabvox.call.ended',
        data: { account_id: @account_id, call_log_id: call_log.id, uniqueid: call_log.uniqueid }
      }
    )
  end
end
