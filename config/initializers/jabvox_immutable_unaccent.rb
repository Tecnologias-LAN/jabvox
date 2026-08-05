# La columna generada search_vector_jabvox depende de la función IMMUTABLE
# jabvox_immutable_unaccent (unaccent(regdictionary, text) es STABLE y Postgres la
# rechaza en columnas GENERATED). schema.rb no serializa funciones, así que un
# `db:schema:load` en una BD limpia crearía la columna antes de existir la función y
# fallaría. Este hook inyecta la definición de la función tras el bloque de
# extensiones del schema volcado, de modo que el load la tenga disponible.
#
# Sobrevive a regeneraciones de schema.rb (no hay que editarlo a mano).
module JabvoxImmutableUnaccentSchemaDumper
  FUNCTION_DEFINITION = <<~RUBY.freeze
    # Función IMMUTABLE para búsqueda insensible a acentos (módulo Jabvox Tickets).
    unless connection.select_value("SELECT to_regprocedure('jabvox_immutable_unaccent(text)') IS NOT NULL")
      execute("CREATE FUNCTION jabvox_immutable_unaccent(text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT AS $func$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $func$")
    end
  RUBY

  def extensions(stream)
    super
    return unless @connection.extension_enabled?('unaccent')

    stream.puts
    FUNCTION_DEFINITION.each_line { |line| stream.puts("  #{line}".rstrip) }
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend(
    JabvoxImmutableUnaccentSchemaDumper
  )
end
