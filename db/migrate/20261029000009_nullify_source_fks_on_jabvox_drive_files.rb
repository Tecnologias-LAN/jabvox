# frozen_string_literal: true

# Los archivos del Drive SOBREVIVEN al borrado de su conversación / contacto /
# mensaje de origen: el archivo queda normal en el Drive (su objeto en MinIO, su
# carpeta y su cuota no se tocan); solo se borran a mano desde la papelera.
#
# Antes, estos tres FKs eran RESTRICT (ON DELETE NO ACTION, el default de Rails).
# Eso BLOQUEABA el borrado de una conversación/contacto que tuviera un adjunto
# indexado en el Drive: el DELETE fallaba con InvalidForeignKey, el DeleteObjectJob
# moría (no tiene fallback para Conversation/Contact) y la conversación "no se
# eliminaba" aunque el frontend ya hubiera dicho "eliminada con éxito".
#
# Solución: ON DELETE SET NULL. Al borrar el origen, el archivo del Drive queda
# huérfano de esas referencias (conversation_id/contact_id/message_id = NULL) pero
# SIGUE EXISTIENDO y visible en el Drive. No se pierde nada ni se libera cuota.
#
# account_id y folder_id NO se tocan (el archivo sigue perteneciendo a la cuenta y
# a su carpeta). sha256/object_key intactos.
class NullifySourceFksOnJabvoxDriveFiles < ActiveRecord::Migration[7.1]
  SOURCES = %i[conversation contact message].freeze

  def up
    SOURCES.each do |source|
      to_table = source.to_s.pluralize.to_sym
      remove_foreign_key :jabvox_drive_files, to_table if foreign_key_exists?(:jabvox_drive_files, to_table)
      add_foreign_key :jabvox_drive_files, to_table, column: "#{source}_id", on_delete: :nullify
    end
  end

  def down
    SOURCES.each do |source|
      to_table = source.to_s.pluralize.to_sym
      remove_foreign_key :jabvox_drive_files, to_table if foreign_key_exists?(:jabvox_drive_files, to_table)
      add_foreign_key :jabvox_drive_files, to_table, column: "#{source}_id"
    end
  end
end
