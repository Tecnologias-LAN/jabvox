# Single source of truth for what gets mirrored to an account's external DB.
#
# Security model:
# - EXCLUDED_MODELS: connection/credential-only models are never exported at all.
# - SENSITIVE_COLUMN_PATTERNS: any column whose name matches (password, secret,
#   token, api_key, access_key, private_key, webhook_secret, credentials, etc.)
#   is stripped from EVERY exported row — even on models that do carry real data.
# - Only columns of exported models pass through; nothing is derived from user input.
module Jabvox::ExternalExport::Catalog
  module_function

  # Models that are pure configuration/credentials — never mirrored.
  EXCLUDED_MODELS = %w[
    JabvoxAiChatConfig JabvoxAiChatModel JabvoxAudioStorage JabvoxCdrConfig
    JabvoxSmsProvider JabvoxSmtpConfig JabvoxVoipConfig JabvoxIntegrationConfig
    JabvoxResponseBotConfig JabvoxSaldoConfig JabvoxFormConfig
    JabvoxAnalyticsDataSource JabvoxAnalyticsDataSourcePermission
    JabvoxLeadSource JabvoxLeadSourceRecord JabvoxExportTarget
    JabvoxAnalyticsQueryCacheEntry JabvoxAnalyticsAuditLog
  ].freeze

  # Column-name patterns that must never leave Jabvox, on any model.
  SENSITIVE_COLUMN_PATTERNS = [
    /password/i, /secret/i, /_token\z/i, /\Atoken\z/i, /api_key/i, /access_key/i,
    /private_key/i, /public_key/i, /webhook_secret/i, /credential/i, /encrypted_/i,
    /\Aotp/i, /pubsub/i, /\Akey\z/i, /bucket_/i, /ssl_ca/i, /verification_pin/i
  ].freeze

  # A jabvox model is exportable when it's an ActiveRecord model, has an account_id,
  # is not in the exclusion list, and is not an encrypted-credentials model.
  #
  # We only memoize once the app is fully booted (all models eager-loaded).
  # During boot the model set may be incomplete, so we never cache a partial
  # result — otherwise a process could permanently miss models that hadn't
  # loaded yet when the initializer ran.
  def exportable_models
    return @exportable_models if @exportable_models

    models = discover_models
    @exportable_models = models if Rails.application.initialized?
    models
  end

  # Force a re-scan (used right after the boot hook wires up the models).
  def reset!
    @exportable_models = nil
  end

  # Safe columns for a model = its DB columns minus the sensitive ones.
  def safe_columns(model)
    model.column_names.reject { |c| sensitive?(c) }
  end

  def sensitive?(column_name)
    SENSITIVE_COLUMN_PATTERNS.any? { |re| column_name.match?(re) }
  end

  # Destination table name for a model (clean names — the DB is per-account, so no
  # account prefix is needed). E.g. JabvoxCallLog -> "jabvox_call_logs".
  def table_name_for(model)
    model.table_name
  end

  def discover_models
    # Always eager-load so the scan sees every model regardless of the load
    # order relative to this initializer (in production the app is already
    # eager-loaded, so this is a cheap no-op).
    Rails.application.eager_load!
    ObjectSpace.each_object(Class).select do |klass|
      klass < ActiveRecord::Base &&
        klass.name.to_s.start_with?('Jabvox') &&
        klass.name.to_s.exclude?('::') &&
        EXCLUDED_MODELS.exclude?(klass.name) &&
        table_exists_with_account?(klass)
    rescue StandardError
      false
    end.uniq(&:name).sort_by(&:name)
  end

  def table_exists_with_account?(klass)
    klass.table_exists? && klass.column_names.include?('account_id') &&
      !encrypted_credentials_model?(klass)
  end

  # Belt-and-suspenders: skip any model that declares encrypted attributes (those
  # are credential stores), even if it slipped past EXCLUDED_MODELS.
  def encrypted_credentials_model?(klass)
    klass.respond_to?(:encrypted_attributes) && klass.encrypted_attributes.present?
  end
end
