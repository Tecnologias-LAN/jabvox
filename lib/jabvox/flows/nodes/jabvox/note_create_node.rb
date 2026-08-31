# frozen_string_literal: true

# jabvox.note.create — nota interna en la ficha de un CONTACTO. No es un mensaje
# de la conversación: solo la ve el equipo.
class Jabvox::Flows::Nodes::Jabvox::NoteCreateNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.note.create'
  label 'Crear nota en contacto'

  def perform
    content = param(:content).to_s.strip
    fail_with!('La nota no puede estar vacía.') if content.blank?

    contact = find_contact!(param(:contactId))
    note = contact.notes.create!(account_id: account.id, content: content)
    { 'id' => note.id, 'contact_id' => contact.id, 'content' => note.content,
      'created_at' => note.created_at.iso8601 }
  end
end
