module Jabvox
  class AffiliateIpWhitelistService
    CACHE_TTL = 5.minutes

    def self.allowed?(affiliate_id, raw_ip)
      client_ip = Jabvox::IpWhitelistService.normalize_ip(raw_ip)
      active_ips = fetch_active_ips(affiliate_id)

      return false if active_ips.nil? || active_ips.empty?
      return true if active_ips.include?('0.0.0.0')

      active_ips.include?(client_ip)
    end

    # Returns true if the IP is allowed by at least one active affiliate in the account.
    # Used to gate the portal page itself before any credentials are entered.
    def self.account_allowed?(account_id, raw_ip)
      client_ip = Jabvox::IpWhitelistService.normalize_ip(raw_ip)

      affiliate_ids = JabvoxAffiliate.where(account_id: account_id, active: true).pluck(:id)
      return false if affiliate_ids.empty?

      JabvoxAffiliateIpWhitelist
        .where(jabvox_affiliate_id: affiliate_ids, is_active: true)
        .where(ip: [client_ip, '0.0.0.0'])
        .exists?
    end

    def self.invalidate_cache(affiliate_id)
      Rails.cache.delete(cache_key(affiliate_id))
    end

    private_class_method def self.fetch_active_ips(affiliate_id)
      Rails.cache.fetch(cache_key(affiliate_id), expires_in: CACHE_TTL) do
        return nil unless JabvoxAffiliateIpWhitelist.exists?(jabvox_affiliate_id: affiliate_id)

        JabvoxAffiliateIpWhitelist.where(jabvox_affiliate_id: affiliate_id, is_active: true).pluck(:ip)
      end
    end

    private_class_method def self.cache_key(affiliate_id)
      "jabvox_affiliate_ip_whitelist_#{affiliate_id}"
    end
  end
end
