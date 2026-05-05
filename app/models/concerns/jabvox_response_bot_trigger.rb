module JabvoxResponseBotTrigger
  extend ActiveSupport::Concern

  included do
    after_create_commit :trigger_jabvox_response_bot
  end

  private

  def trigger_jabvox_response_bot
    return unless message_type.to_s == 'incoming'
    return if content.blank?
    return if private?

    Jabvox::ResponseBotJob.perform_later(id)
  end
end
