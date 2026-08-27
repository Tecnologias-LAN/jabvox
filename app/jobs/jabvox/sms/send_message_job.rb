# frozen_string_literal: true

# Envía UN SMS de una campaña a un contacto. Corre en la cola aislada jabvox_sms, así el
# HTTP bloqueante al proveedor (hasta 15s) nunca ocupa un hilo de Puma. Reintentable de
# forma independiente: si un SMS falla por red, se reintenta sin afectar a los demás.
module Jabvox
  module Sms
    class SendMessageJob < ApplicationJob
      include Jabvox::AccountFairShare
      queue_as :jabvox_sms

      # Reintentos ante fallos transitorios de red del proveedor (backoff exponencial).
      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      # Fairness: una campaña masiva de una cuenta no acapara el worker sms de las demás.
      fair_share_limit 15
      fair_share_env 'JABVOX_SMS_MAX_INFLIGHT_PER_ACCOUNT'

      def perform(campaign_id, contact_id)
        campaign = JabvoxSmsCampaign.find_by(id: campaign_id)
        return if campaign.nil?

        provider = campaign.jabvox_sms_provider
        return unless provider&.active?

        contact = campaign.account.contacts.find_by(id: contact_id)
        return if contact.nil? || contact.phone_number.blank?

        with_account_fair_share(campaign.account_id) do
          message = Jabvox::SmsSenderService.interpolate(campaign.message, contact)
          Jabvox::SmsSenderService.new(provider).send_sms(
            phone: contact.phone_number,
            message: message,
            campaign: campaign,
            contact: contact,
            account: campaign.account
          )
        end
      end
    end
  end
end
