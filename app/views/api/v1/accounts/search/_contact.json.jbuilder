json.email jabvox_mask('email', contact.email)
json.id contact.id
json.name jabvox_mask('name', contact.name)
json.phone_number jabvox_mask('phone', contact.phone_number)
json.identifier contact.identifier
json.additional_attributes jabvox_mask_attrs(contact.additional_attributes)
json.last_activity_at contact.last_activity_at&.to_i
