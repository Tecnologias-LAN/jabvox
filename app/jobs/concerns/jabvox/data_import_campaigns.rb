# Extensión Jabvox de DataImportJob: tras importar los contactos, les asigna la campaña que
# venía en el CSV. Vive fuera del job del núcleo para no tocar la lógica de importación
# original.
#
# Antes creaba un JabvoxLead por contacto con esa campaña; al vivir la campaña en el propio
# contacto, basta con asignarla.
module Jabvox::DataImportCampaigns
  def create_jabvox_leads(contacts, campaign_names)
    contacts.each_with_index do |item, idx|
      # Tras el refactor de etiquetas de upstream, cada entrada es { contact:, labels: }.
      contact = item.is_a?(Hash) ? item[:contact] : item
      next if contact.nil? || contact.id.blank?

      campaign_name = campaign_names[idx]
      next if campaign_name.blank?

      campaign = JabvoxCampaign.find_or_create_by!(account: @data_import.account, name_jabvox: campaign_name)
      # No se pisa una campaña ya asignada: el CSV completa, no reescribe.
      contact.update!(jabvox_campaign: campaign) if contact.jabvox_campaign_id.nil?
    end
  rescue StandardError => e
    Rails.logger.error("Jabvox: asignación de campaña en la importación falló: #{e.message}")
  end
end
