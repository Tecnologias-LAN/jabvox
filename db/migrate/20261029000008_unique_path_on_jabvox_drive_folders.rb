# Previene carpetas DUPLICADas del Drive. El índice único previo era
# [account_id, parent_id, name], pero la carpeta raíz "contactos" tiene parent_id
# NULL y en PostgreSQL dos NULL no colisionan en un índice único → bajo concurrencia
# (varios adjuntos entrando a la vez) se creaban varias raíces, y en cascada se
# duplicaban las subcarpetas de contacto/bandeja.
#
# `path` es único por carpeta y NUNCA es NULL (/contactos/, /contactos/<c>/<b>/),
# así que un índice único sobre [account_id, path] cierra el agujero del NULL.
#
# Antes de crear el índice, se COLAPSAN los duplicados existentes: se conserva la
# carpeta más antigua (menor id) de cada path y se reapuntan sus hijos y archivos.
class UniquePathOnJabvoxDriveFolders < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    dedupe_existing!

    return if index_exists?(:jabvox_drive_folders, %i[account_id path], name: 'idx_drive_folders_unique_path')

    add_index :jabvox_drive_folders, %i[account_id path], unique: true,
                                                          name: 'idx_drive_folders_unique_path',
                                                          algorithm: :concurrently
  end

  def down
    remove_index :jabvox_drive_folders, name: 'idx_drive_folders_unique_path', if_exists: true
  end

  private

  # Colapsa carpetas con el mismo (account_id, path): deja la de menor id (canónica)
  # y mueve hijos/archivos de las duplicadas a la canónica, luego borra las duplicadas.
  def dedupe_existing!
    rows = select_all(<<~SQL.squish)
      SELECT account_id, path, array_agg(id ORDER BY id) AS ids
      FROM jabvox_drive_folders
      GROUP BY account_id, path
      HAVING COUNT(*) > 1
    SQL

    rows.each do |row|
      ids = Array(row['ids'].is_a?(String) ? row['ids'].delete('{}').split(',') : row['ids']).map(&:to_i)
      keep = ids.first
      dups = ids[1..] || []
      next if dups.empty?

      dup_list = dups.join(',')
      # Reapuntar archivos y subcarpetas de las duplicadas a la canónica.
      execute("UPDATE jabvox_drive_files SET folder_id = #{keep} WHERE folder_id IN (#{dup_list})")
      execute("UPDATE jabvox_drive_folders SET parent_id = #{keep} WHERE parent_id IN (#{dup_list})")
      execute("DELETE FROM jabvox_drive_folders WHERE id IN (#{dup_list})")
    end
  end
end
