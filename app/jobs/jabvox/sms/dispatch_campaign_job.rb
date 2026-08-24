# frozen_string_literal: true

# Dispatcher de una campaña de SMS masivo. Reemplaza el bucle SÍNCRONO que corría dentro
# del request HTTP (bloqueaba Puma y perdía SMS si el request moría). Ahora corre en la
# cola aislada jabvox_sms y hace FAN-OUT: un SendMessageJob por SMS (reintentable).
# El envío real (HTTP al proveedor) ocurre en SendMessageJob, no aquí.
#
# Recibe los contact_ids YA resueltos por el controlador (reusa su lógica de filtrado de
# leads/contactos, sin duplicarla). Procesa en lotes para no cargar todo en memoria.
module Jabvox
  module Sms
    class DispatchCampaignJob < ApplicationJob
      queue_as :jabvox_sms

      def perform(campaign_id, contact_ids)
        campaign = JabvoxSmsCampaign.find_by(id: campaign_id)
        return if campaign.nil?

        provider = campaign.jabvox_sms_provider
        return mark_failed(campaign, 'no_active_provider') unless provider&.active?

        count = 0
        # find_each sobre los ids resueltos: memoria acotada aunque sean 100k contactos.
        campaign.account.contacts
                .where(id: Array(contact_ids))
                .where.not(phone_number: [nil, ''])
                .find_each do |contact|
          Jabvox::Sms::SendMessageJob.perform_later(campaign.id, contact.id)
          count += 1
        end

        campaign.update!(status: 'completed')
        Rails.logger.info("[Sms::DispatchCampaign] campaign=#{campaign.id} encolados=#{count}")
      end

      private

      def mark_failed(campaign, reason)
        campaign.update(status: 'failed')
        Rails.logger.warn("[Sms::DispatchCampaign] campaign=#{campaign.id} #{reason}")
      end
    end
  end
end
