module Jabvox
  class IpWhitelistService
    CACHE_TTL = 5.minutes

    def self.allowed?(account_id, raw_ip)
      client_ip = normalize_ip(raw_ip)
      active_ips = fetch_active_ips(account_id)

      return true if active_ips.nil?  # no whitelist records at all → allow all
      return true if active_ips.include?('0.0.0.0')

      active_ips.include?(client_ip)
    end

    def self.invalidate_cache(account_id)
      Rails.cache.delete(cache_key(account_id))
    end

    def self.normalize_ip(raw_ip)
      return '' if raw_ip.blank?

      ip = raw_ip.to_s.split(',').first.to_s.strip
      ip = ip.gsub(/:\d+$/, '') if ip.include?('.') && ip.include?(':')
      ip = '127.0.0.1' if ip == '::1'
      ip = ip.sub(/\A::ffff:/i, '') if ip.start_with?('::ffff:', '::FFFF:')
      ip
    end

    def self.extract_client_ip(request)
      forwarded = request.env['HTTP_X_FORWARDED_FOR'].presence
      if forwarded
        normalize_ip(forwarded.split(',').first)
      else
        normalize_ip(request.env['HTTP_X_REAL_IP'].presence || request.ip)
      end
    end

    private_class_method def self.fetch_active_ips(account_id)
      Rails.cache.fetch(cache_key(account_id), expires_in: CACHE_TTL) do
        next nil unless JabvoxIpWhitelist.exists?(account_id: account_id)

        JabvoxIpWhitelist.where(account_id: account_id, is_active: true).pluck(:ip)
      end
    end

    private_class_method def self.cache_key(account_id)
      "jabvox_ip_whitelist_#{account_id}"
    end
  end
end
