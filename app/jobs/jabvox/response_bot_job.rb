class Jabvox::ResponseBotJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    Jabvox::ResponseBotService.new(message).process
  end
end
