# frozen_string_literal: true

# `settings` now uses ActiveRecord::Encryption (it holds provider credentials
# like the Jabvox IA api_key). Existing rows were written as plaintext JSON, so
# re-save them once to store the encrypted form. Idempotent: AR supports reading
# not-yet-encrypted values (config.active_record.encryption.support_unencrypted_data)
# so this can run safely; each row is re-written through the model to encrypt it.
class EncryptIntegrationsHookSettings < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    return unless Jabvox.encryption_configured?

    Integrations::Hook.find_each do |hook|
      # Touch settings so AR persists the encrypted representation. update_column
      # skips validations/callbacks (no re-validation of the API key over the net).
      hook.update_column(:settings, hook.settings) # rubocop:disable Rails/SkipsModelValidations
    rescue StandardError => e
      Rails.logger.warn("[encrypt-hook-settings] hook ##{hook.id}: #{e.class} #{e.message}")
    end
  end

  def down
    # No-op: we don't revert to plaintext.
  end
end
