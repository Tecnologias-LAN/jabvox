# frozen_string_literal: true

# CRUD de carpetas del Drive. Toda operación está acotada a la cuenta: las
# carpetas se buscan y crean SIEMPRE dentro de `account.jabvox_drive_folders`.
#
# Las carpetas de sistema (raíz "Contactos" y la carpeta canónica de cada
# contacto) no se pueden renombrar ni borrar: son creadas/garantizadas por el
# modelo (JabvoxDriveFolder.for_contact) y sostienen el árbol de contactos.
module Jabvox
  module Drive
    class FolderService
      class Error < StandardError; end
      class SystemFolderError < Error; end

      attr_reader :account

      def initialize(account)
        raise ArgumentError, 'account requerido' if account.nil?

        @account = account
      end

      # Crea una carpeta normal (no de sistema) bajo `parent` (o en la raíz).
      def create!(name:, parent_id: nil, created_by: nil)
        parent = find_parent(parent_id)
        account.jabvox_drive_folders.create!(
          name: safe_name(name),
          parent: parent,
          created_by: created_by,
          system_folder: false
        )
      end

      def rename!(folder, name:)
        guard_system!(folder)
        folder.update!(name: safe_name(name))
        folder
      end

      # Mueve una carpeta a otro padre (o a la raíz con parent_id nil).
      def move!(folder, parent_id:)
        guard_system!(folder)
        parent = find_parent(parent_id)
        raise Error, 'no se puede mover una carpeta dentro de sí misma' if parent && would_create_cycle?(folder, parent)

        folder.update!(parent: parent)
        folder
      end

      # Borra una carpeta normal. Sus archivos quedan con folder_id nil (dependent
      # :nullify en el modelo); los objetos físicos NO se tocan aquí.
      def destroy!(folder)
        guard_system!(folder)
        folder.destroy!
        true
      end

      private

      def find_parent(parent_id)
        return nil if parent_id.blank?

        account.jabvox_drive_folders.find(parent_id)
      end

      def guard_system!(folder)
        raise SystemFolderError, 'carpeta de sistema: no se puede modificar' if folder.system_folder?
      end

      # Evita que una carpeta se mueva bajo uno de sus descendientes.
      def would_create_cycle?(folder, new_parent)
        node = new_parent
        while node
          return true if node.id == folder.id

          node = node.parent
        end
        false
      end

      def safe_name(name)
        clean = name.to_s.strip.tr("\u0000", '').delete('/')
        raise Error, 'nombre de carpeta inválido' if clean.blank?

        clean.first(255)
      end
    end
  end
end
