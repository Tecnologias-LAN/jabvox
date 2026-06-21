module JabvoxResponseBotTrigger
  extend ActiveSupport::Concern

  included do
    after_create_commit :trigger_jabvox_response_bot
  end

  private

  def trigger_jabvox_response_bot
    return unless message_type.to_s == 'incoming'
    return if private?

    has_media = attachments.any? { |a| %w[audio image].include?(a.file_type.to_s) }
    return if content.blank? && !has_media

    Jabvox::ResponseBotJob.set(wait: 10.seconds).perform_later(id)
  end
end
