# frozen_string_literal: true

# jabvox.campaign.add_lead — asocia un lead a una campaña POR NOMBRE (se crea si
# no existe), igual que `update_details` del panel. El select entrega un id: se
# resuelve a nombre dentro de la cuenta.
class Jabvox::Flows::Nodes::Jabvox::CampaignAddLeadNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.campaign.add_lead'
  label 'Asociar Lead a Campaña'

  def perform
    lead = find_lead!(param(:leadId), 'el ID interno del lead')
    campaign = JabvoxCampaign.find_or_create_by!(account: account, name_jabvox: campaign_name)
    lead.update!(jabvox_campaign: campaign)
    { 'leadId' => lead.id, 'lead_number' => lead.lead_number,
      'campaign_id' => campaign.id, 'campaign' => campaign.name_jabvox }
  end

  private

  # Un valor NUMÉRICO se interpreta como id de campaña de la cuenta; cualquier
  # otro texto es el NOMBRE (y se crea la campaña si aún no existe).
  def campaign_name
    raw = first_filled(param(:campaign))
    fail_with!(missing_campaign_message) if raw.blank?
    return raw unless /\A\d+\z/.match?(raw)

    campaign = account.jabvox_campaigns.find_by(id: raw.to_i)
    fail_with!(unknown_campaign_message(raw)) if campaign.nil?

    campaign.name_jabvox
  end

  def missing_campaign_message
    'Falta la campaña: llegó vacía. Elige una campaña de la lista o escribe el nombre de una nueva.'
  end

  def unknown_campaign_message(raw)
    "La campaña #{raw} no existe en esta cuenta. Elige una de la lista o escribe el NOMBRE de una " \
      'campaña nueva (un número se interpreta como id de campaña, no como nombre).'
  end
end
