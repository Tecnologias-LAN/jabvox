require 'digest'

# Query result cache. Small/hot results live in Redis (via Redis::Alfred); the durable
# jabvox_analytics_query_cache table is used as a fallback for large payloads. Keys are
# scoped per account / data source / query / user / filter set.
class Jabvox::Analytics::CacheService
  # Payloads above this JSON size go to the durable table instead of Redis.
  REDIS_MAX_BYTES = 256 * 1024

  def initialize(account:, data_source: nil, user: nil)
    @account = account
    @data_source = data_source
    # user se conserva por compatibilidad de firma, pero NO entra en la clave: ver key_for.
    @user = user
  end

  # La clave es por cuenta + fuente + consulta, NO por usuario. El resultado de una consulta
  # (SQL o spec) es idéntico para cualquier usuario con acceso —el control de acceso se aplica
  # aguas arriba, antes de ejecutar—, así que cachear por usuario multiplicaría ejecuciones
  # idénticas contra la BD externa por el número de usuarios (mata la escalabilidad cuando
  # muchos usuarios abren el mismo dashboard). Compartir por cuenta mantiene el aislamiento
  # entre cuentas (account.id está en la clave) y da reuso máximo dentro de la cuenta.
  def key_for(parts)
    digest = Digest::SHA256.hexdigest(parts.to_json)
    ds = @data_source&.id || 'none'
    "analytics:acct:#{@account.id}:ds:#{ds}:q:#{digest}"
  end

  def fetch(parts, ttl_seconds:)
    key = key_for(parts)
    cached = read(key)
    return cached if cached

    value = yield
    write(key, value, ttl_seconds)
    value
  end

  def read(key)
    raw = Redis::Alfred.get(key)
    return JSON.parse(raw, symbolize_names: true) if raw.present?

    durable = JabvoxAnalyticsQueryCacheEntry.fresh.find_by(account_id: @account.id, cache_key_jabvox: key)
    durable&.result_jabvox&.deep_symbolize_keys
  end

  def write(key, value, ttl_seconds)
    json = value.to_json
    if json.bytesize <= REDIS_MAX_BYTES
      Redis::Alfred.setex(key, json, ttl_seconds)
    else
      store_durable(key, value, ttl_seconds)
    end
  end

  def store_durable(key, value, ttl_seconds)
    entry = JabvoxAnalyticsQueryCacheEntry.find_or_initialize_by(account_id: @account.id, cache_key_jabvox: key)
    entry.data_source = @data_source
    entry.result_jabvox = value
    entry.row_count_jabvox = value.is_a?(Hash) ? value[:row_count].to_i : 0
    entry.expires_at_jabvox = Time.current + ttl_seconds
    entry.save!
  end
end
