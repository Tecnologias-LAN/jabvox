# Delivers web-push notifications for a new internal-chat message off the request
# cycle, so sending a message stays fast even with many recipients/subscriptions.
class Jabvox::InternalChatPushJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = JabvoxInternalMessage.find_by(id: message_id)
    return unless message

    chat = message.chat
    sender = message.sender
    return unless chat && sender

    Jabvox::InternalChatPushService.new(chat: chat, message: message, sender: sender).perform
  end
end
