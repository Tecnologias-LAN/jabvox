# Normalizes a phone number for DIALING through Asterisk (AMI Originate).
#
# The PBX dial plan expects the number WITHOUT the "+": the country prefix is
# kept, only the "+" (and any spacing/formatting) is stripped. This mirrors how
# SMS already sanitizes numbers (Jabvox::SmsSenderService#sanitize_phone).
#
#   "+573054473380"  -> "573054473380"
#   "+57 305 447 33" -> "5730544733"
#   "3054473380"     -> "3054473380"   (already without +, left as-is)
#
# When a `prefix` is given (e.g. "57"), it is PREPENDED to numbers that don't
# already carry a country code — the case for custom fields that store the bare
# local number. A number that already starts with the prefix and is long enough
# is left as-is, so a prefix is never doubled.
module Jabvox
  module PhoneNormalizer
    module_function

    # Strip formatting only (no prefix logic). Used when the stored value is
    # already E.164 (contact.phone_number).
    def for_dialing(phone)
      phone.to_s.gsub(/[+\s\-()]/, '')
    end

    # Full normalization for an arbitrary field value with an optional country
    # prefix. Returns bare digits ready for the dial plan, or nil if there are
    # no usable digits.
    def normalize(value, prefix = nil)
      digits = value.to_s.gsub(/[^\d+]/, '') # keep digits and a leading +
      had_plus = digits.start_with?('+')
      digits = digits.gsub('+', '')
      return nil if digits.blank?

      pfx = prefix.to_s.gsub(/\D/, '')
      return digits if pfx.blank?

      # Already carries the country code: it had a "+", or it starts with the
      # prefix and is long enough to plausibly include it (prefix + a local
      # number of at least 6 digits). Otherwise prepend the prefix.
      return digits if had_plus
      return digits if digits.start_with?(pfx) && digits.length > pfx.length + 6

      "#{pfx}#{digits}"
    end
  end
end
