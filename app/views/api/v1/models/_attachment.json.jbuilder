attachment_data = attachment.push_event_data

json.id attachment_data[:id]
json.message_id attachment_data[:message_id]
json.thumb_url attachment_data[:thumb_url]
json.data_url attachment_data[:data_url]
json.file_size attachment_data[:file_size]
json.file_type attachment_data[:file_type]
json.extension attachment_data[:extension]
json.width attachment_data[:width]
json.height attachment_data[:height]
json.created_at attachment.message.created_at.to_i
json.sender attachment.message.sender.push_event_data if attachment.message.sender
# jabvox-drive: adjunto retenido por falta de espacio (overflow). El front muestra
# "no se puede ver por falta de espacio" en vez de la imagen.
if attachment_data[:storage_blocked]
  json.storage_blocked true
  json.storage_state attachment_data[:storage_state]
end
