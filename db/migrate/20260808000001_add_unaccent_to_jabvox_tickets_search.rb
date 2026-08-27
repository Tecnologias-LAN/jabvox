# Búsqueda de tickets insensible a acentos (produccion == producción):
# - Habilita la extensión unaccent de Postgres.
# - Define un wrapper IMMUTABLE (unaccent(regdictionary, text) es STABLE en el
#   catálogo y Postgres rechaza usarlo en una columna GENERATED; el wrapper la marca
#   IMMUTABLE explícitamente).
# - Recrea la columna tsvector generada aplicando el wrapper.
# La función se re-crea también en el schema loader (ver db/seeds no aplica; se usa
# un initializer idempotente) para que db:schema:load la tenga disponible.
# La query de pg_search aplica la misma normalización en el modelo.
class AddUnaccentToJabvoxTicketsSearch < ActiveRecord::Migration[7.1]
  def up
    enable_extension 'unaccent' unless extension_enabled?('unaccent')
    create_immutable_unaccent
    rebuild_search_vector(unaccented: true)
  end

  def down
    rebuild_search_vector(unaccented: false)
    execute('DROP FUNCTION IF EXISTS jabvox_immutable_unaccent(text)')
    # No se deshabilita la extensión: otros objetos podrían depender de ella.
  end

  private

  # Wrapper IMMUTABLE sobre unaccent con diccionario explícito, apto para columnas
  # generadas e índices.
  def create_immutable_unaccent
    execute(<<~SQL.squish)
      CREATE OR REPLACE FUNCTION jabvox_immutable_unaccent(text)
      RETURNS text
      LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
      AS $func$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $func$
    SQL
  end

  # Recrea la columna tsvector generada. Con unaccent: normaliza acentos antes de
  # to_tsvector. Sin unaccent: vuelve a la versión previa.
  def rebuild_search_vector(unaccented:)
    execute('ALTER TABLE jabvox_tickets DROP COLUMN IF EXISTS search_vector_jabvox')

    title = column_expression('title_jabvox', unaccented)
    description = column_expression('description_jabvox', unaccented)

    execute(<<~SQL.squish)
      ALTER TABLE jabvox_tickets
      ADD COLUMN search_vector_jabvox tsvector
      GENERATED ALWAYS AS (
        setweight(to_tsvector('simple', #{title}), 'A') ||
        setweight(to_tsvector('simple', #{description}), 'B')
      ) STORED
    SQL

    add_index :jabvox_tickets, :search_vector_jabvox,
              name: 'idx_tickets_search_vector', using: :gin
  end

  def column_expression(column, unaccented)
    coalesced = "coalesce(#{column}, '')"
    unaccented ? "jabvox_immutable_unaccent(#{coalesced})" : coalesced
  end
end
