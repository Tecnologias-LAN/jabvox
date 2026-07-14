# Resolves the phone number to actually dial for a lead, honoring the
# configured "dial field" and prefix (VoIP config for click-to-call, or the
# campaign for the dialer).
#
#   field  : 'phone' (or blank) → the contact's phone_number (already E.164).
#            any other value    → a custom column key on the lead's
#                                 custom_fields_jabvox (e.g. 'movil_2_c'),
#                                 which usually stores the bare local number.
#   prefix : country code to prepend to bare numbers (only applied to custom
#            fields, since phone_number is already E.164).
#
# Returns bare digits ready for Asterisk (no "+"), or nil when there's nothing
# usable. The field key is sanitized to the [a-z0-9_] slug used everywhere, so
# it can never be used to reach outside custom_fields_jabvox.
module Jabvox
  module DialNumberResolver
    module_function

    PHONE_FIELD = 'phone'

    # lead: a JabvoxLead (responds to #contact and #custom_fields_jabvox).
    def resolve(lead:, field:, prefix: nil)
      key = sanitize_field(field)

      if key.blank? || key == PHONE_FIELD
        # Contact phone is stored E.164 with "+": just strip formatting.
        Jabvox::PhoneNormalizer.for_dialing(lead&.contact&.phone_number).presence
      else
        raw = (lead&.custom_fields_jabvox || {})[key]
        Jabvox::PhoneNormalizer.normalize(raw, prefix)
      end
    end

    # Same as resolve but from an already-known raw value (used when the caller
    # already has the value, e.g. a dialer campaign contact row).
    def resolve_value(raw:, field:, prefix: nil)
      key = sanitize_field(field)
      if key.blank? || key == PHONE_FIELD
        Jabvox::PhoneNormalizer.for_dialing(raw).presence
      else
        Jabvox::PhoneNormalizer.normalize(raw, prefix)
      end
    end

    def sanitize_field(field)
      field.to_s.strip.downcase.gsub(/[^a-z0-9_]/, '')
    end
  end
end
