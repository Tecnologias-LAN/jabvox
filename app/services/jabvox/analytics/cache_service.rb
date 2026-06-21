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
    @user = user
  end

  def key_for(parts)
    digest = Digest::SHA256.hexdigest(parts.to_json)
    ds = @data_source&.id || 'none'
    uid = @user&.id || 'none'
    "analytics:acct:#{@account.id}:ds:#{ds}:u:#{uid}:q:#{digest}"
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
