# Resolves the correct adapter subclass for a data source's engine.
# Adding a new engine = a new subclass + an entry here; callers are untouched.
class Jabvox::Analytics::AdapterFactory
  ADAPTERS = {
    'postgresql' => Jabvox::Analytics::Adapters::PostgresAdapter,
    'mysql' => Jabvox::Analytics::Adapters::MysqlAdapter,
    'mariadb' => Jabvox::Analytics::Adapters::MysqlAdapter,
    'sqlite' => Jabvox::Analytics::Adapters::SqliteAdapter,
    'sqlserver' => Jabvox::Analytics::Adapters::SqlserverAdapter
  }.freeze

  def self.for(data_source)
    klass = ADAPTERS[data_source.engine_jabvox.to_s]
    raise ArgumentError, "Motor no soportado: #{data_source.engine_jabvox}" unless klass

    klass.new(data_source)
  end

  def self.supported_engine?(engine)
    ADAPTERS.key?(engine.to_s)
  end
end
