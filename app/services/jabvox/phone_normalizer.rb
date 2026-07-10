# Normalizes a phone number for DIALING through Asterisk (AMI Originate).
#
# Contacts are stored in E.164 with a leading "+" (e.g. "+573054473380"), but
# the PBX dial plan expects the number WITHOUT the "+": the country prefix is
# kept, only the "+" (and any spacing/formatting) is stripped. This mirrors how
# SMS already sanitizes numbers (Jabvox::SmsSenderService#sanitize_phone), so
# click-to-call and the dialer dial the exact same digits SMS would send.
#
#   "+573054473380"  -> "573054473380"
#   "+57 305 447 33" -> "57305447 33" stripped -> "5730544733"
#   "3054473380"     -> "3054473380"   (already without +, left as-is)
#
# Only "+", whitespace, hyphens and parentheses are removed; the digits (prefix
# included) are never altered.
module Jabvox
  module PhoneNormalizer
    module_function

    def for_dialing(phone)
      phone.to_s.gsub(/[+\s\-()]/, '')
    end
  end
end
