# Returns a data source's schema (tables/views + columns), cached in Redis for a short TTL
# to avoid hammering the external DB on every UI expand.
class Jabvox::Analytics::IntrospectionService
  CACHE_TTL = 10.minutes.to_i

  def initialize(data_source)
    @data_source = data_source
  end

  def call(refresh: false)
    cache = Jabvox::Analytics::CacheService.new(account: @data_source.account, data_source: @data_source)
    key = cache.key_for(['schema', @data_source.updated_at.to_i])

    if refresh
      schema = introspect
      cache.write(key, { schema: schema }, CACHE_TTL)
      return schema
    end

    cache.fetch(['schema', @data_source.updated_at.to_i], ttl_seconds: CACHE_TTL) do
      { schema: introspect }
    end[:schema]
  end

  private

  def introspect
    Jabvox::Analytics::AdapterFactory.for(@data_source).schema_introspection
  end
end
