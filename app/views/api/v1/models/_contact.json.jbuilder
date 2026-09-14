json.additional_attributes jabvox_mask_attrs(resource.additional_attributes)
json.availability_status resource.availability_status
json.email jabvox_mask('email', resource.email)
json.id resource.id
json.name jabvox_mask('name', resource.name)
json.phone_number jabvox_mask('phone', resource.phone_number)
# El teléfono en sus tres piezas: prefijo (del país), número local y E.164.
# Pasan por la MISMA máscara que phone_number: si el agente no puede ver el
# teléfono, tampoco puede reconstruirlo juntando las partes.
json.phone_country_code jabvox_mask('phone', resource.phone_country_code_jabvox)
json.phone_national jabvox_mask('phone', resource.phone_national_jabvox)
json.blocked resource.blocked
json.identifier resource.identifier
json.company_id resource.company_id if Current.account&.feature_enabled?('companies')
json.thumbnail resource.avatar_url
json.custom_attributes resource.custom_attributes
json.last_activity_at resource.last_activity_at.to_i if resource[:last_activity_at].present?
json.created_at resource.created_at.to_i if resource[:created_at].present?
# we only want to output contact inbox when its /contacts endpoints
if defined?(with_contact_inboxes) && with_contact_inboxes.present?
  json.contact_inboxes do
    json.array! resource.contact_inboxes do |contact_inbox|
      json.partial! 'api/v1/models/contact_inbox', formats: [:json], resource: contact_inbox
    end
  end
end
