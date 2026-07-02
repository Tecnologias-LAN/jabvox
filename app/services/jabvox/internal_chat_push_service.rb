# Sends a browser web-push notification to the recipients of a new internal-chat
# message (everyone in the chat except the sender). Mirrors the conversation push
# path but is self-contained for the internal chat. Failures per subscription are
# isolated and expired subscriptions are cleaned up.
class Jabvox::InternalChatPushService
  pattr_initialize [:chat!, :message!, :sender!]

  def perform
    return unless VapidService.public_key

    recipient_user_ids.each do |user_id|
      NotificationSubscription.where(user_id: user_id).find_each do |subscription|
        send_browser_push(subscription)
      end
    end
  end

  private

  def recipient_user_ids
    chat.members.where.not(user_id: sender.id).pluck(:user_id)
  end

  def push_title
    sender.name.presence || 'Jabvox'
  end

  def push_body
    body = message.content.to_s.strip
    body.length > 140 ? "#{body[0, 137]}…" : body
  end

  def push_url
    # Deep link to the internal chat; the SW focuses/opens this URL on click.
    "/app/accounts/#{chat.account_id}/jabvox/internal-chat"
  end

  def push_message
    { title: push_title, body: push_body, tag: "internal_chat_#{chat.id}", url: push_url }
  end

  def send_browser_push(subscription)
    return unless subscription.browser_push?

    WebPush.payload_send(
      message: JSON.generate(push_message),
      endpoint: subscription.subscription_attributes['endpoint'],
      p256dh: subscription.subscription_attributes['p256dh'],
      auth: subscription.subscription_attributes['auth'],
      vapid: {
        subject: push_url,
        public_key: VapidService.public_key,
        private_key: VapidService.private_key
      },
      ssl_timeout: 5, open_timeout: 5, read_timeout: 5
    )
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized
    subscription.destroy!
  rescue StandardError => e
    Rails.logger.error("[InternalChatPush] subscription=#{subscription.id} error=#{e.message}")
  end
end
