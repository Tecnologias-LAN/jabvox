module CacheKeysHelper
  def get_prefixed_cache_key(account_id, key)
    "idb-cache-key-account-#{account_id}-#{key}"
  end

  def fetch_value_for_key(account_id, key)
    prefixed_cache_key = get_prefixed_cache_key(account_id, key)
    value_from_cache = Redis::Alfred.get(prefixed_cache_key)

    return value_from_cache if value_from_cache.present?

    # Self-heal: la llave no existe/expiró → escribe una fresca (epoch actual) y devuélvela.
    # NUNCA devolver un constante repetido aquí: el navegador persiste el valor devuelto en
    # IndexedDB y un constante repetido revalida la cache local vieja PARA SIEMPRE (bug
    # 2026-09-21: etiquetas congeladas en el navegador del cliente Zafiro).
    # setex(key, value, expiry) — mismo orden y TTL que CacheKeys#update_cache_key_for_account.
    fresh = Time.now.utc.to_i.to_s
    Redis::Alfred.setex(prefixed_cache_key, fresh, CacheKeys::CACHE_KEYS_EXPIRY)
    fresh
  rescue StandardError
    # Redis caído: devuelve un valor único para que el cliente refetchee de la red en vez de
    # servir cache local vieja (mejor datos frescos que cache congelada).
    Time.now.utc.to_i.to_s
  end
end
