class Webhooks::SmsController < ActionController::API
  # Bandwidth no firma sus webhooks con HMAC (a diferencia de Meta/Shopify/TikTok), así que
  # la única defensa disponible es un token propio incluido en la URL que el admin configura
  # en el panel de Bandwidth (ver Channel::Sms#valid_webhook_token? e Inbox#callback_webhook_url).
  # Fail-closed: sin canal o sin token válido, se rechaza antes de encolar nada.
  before_action :authenticate_channel!

  def process_payload
    Webhooks::SmsEventsJob.perform_later(params['_json']&.first&.to_unsafe_hash)
    head :ok
  end

  private

  def authenticate_channel!
    channel = Channel::Sms.find_by(phone_number: "+#{params[:phone_number]}")
    head :unauthorized and return if channel.blank?
    head :unauthorized and return unless channel.valid_webhook_token?(params[:token])
  end
end
