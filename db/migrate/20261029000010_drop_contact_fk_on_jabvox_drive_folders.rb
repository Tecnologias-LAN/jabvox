# frozen_string_literal: true

# La carpeta de un contacto SOBREVIVE al borrado del contacto y CONSERVA su
# contact_id (referencia histórica), para poder pintar la bolita roja "contacto
# eliminado" sin perder qué contacto era. Por eso contact_id deja de tener un FK:
#
# - Con FK RESTRICT (lo que había): borrar el contacto fallaba con InvalidForeignKey
#   → el contacto "no se eliminaba" y la carpeta/archivos quedaban bloqueando.
# - Con FK ON DELETE SET NULL: el borrado funciona pero se PIERDE contact_id, así que
#   no se podría distinguir una carpeta de contacto-borrado de una carpeta manual.
#
# Solución: quitar la constraint y dejar contact_id como columna simple. El contacto
# puede borrarse; la carpeta conserva su contact_id. source_alive se calcula
# comparando contra los contactos que AÚN existen (ver FoldersController). El índice
# [account_id, contact_id] se conserva (lo usa for_contact).
class DropContactFkOnJabvoxDriveFolders < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :jabvox_drive_folders, :contacts if foreign_key_exists?(:jabvox_drive_folders, :contacts)
  end

  def down
    add_foreign_key :jabvox_drive_folders, :contacts unless foreign_key_exists?(:jabvox_drive_folders, :contacts)
  end
end
