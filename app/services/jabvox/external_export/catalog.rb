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
    JabvoxLeadSource JabvoxExportTarget JabvoxExportSyncLog
    JabvoxAnalyticsQueryCacheEntry JabvoxAnalyticsAuditLog
  ].freeze
  # NOTE: JabvoxLeadSourceRecord is intentionally NOT excluded. Unlike JabvoxLeadSource
  # (connection credentials), the record holds only the business mapping
  # external_id_jabvox <-> jabvox_lead_id — no credentials — so it IS exported so the
  # CRM can reconcile a lead to its origin row. It has account_id (auto-scan takes it).

  # Specific columns excluded per model even though their name doesn't match a
  # sensitive pattern: JSON blobs that can carry integration tokens / external
  # references we don't want mirrored (e.g. Slack ids in external_source_ids).
  EXCLUDED_COLUMNS_BY_MODEL = {
    'Message' => %w[external_source_ids],
    # Users are exported for agent attribution, but never their credentials or
    # auth/session artifacts. `tokens` is the Devise auth-token store (a
    # credential); provider/uid + sign-in IPs are auth/session data we don't
    # mirror. Names/emails DO go so the CRM can show who did what.
    'User' => %w[
      tokens provider uid current_sign_in_ip last_sign_in_ip
      remember_created_at consumed_timestep unconfirmed_email
      confirmation_sent_at confirmed_at sign_in_count
      current_sign_in_at last_sign_in_at ui_settings
    ].freeze
  }.freeze

  # Column-name patterns that must never leave Jabvox, on any model.
  SENSITIVE_COLUMN_PATTERNS = [
    /password/i, /secret/i, /_token\z/i, /\Atoken\z/i, /api_key/i, /access_key/i,
    /private_key/i, /public_key/i, /webhook_secret/i, /credential/i, /encrypted_/i,
    /\Aotp/i, /pubsub/i, /\Akey\z/i, /bucket_/i, /ssl_ca/i, /verification_pin/i,
    # References to a token (a token FK still points at a credential) and internal
    # infrastructure URLs (webhooks are our automation endpoints, not customer data).
    /access_token/i, /_token_id/i, /webhook_url/i, /webhook/i
  ].freeze

  # Non-Jabvox core models that must also be mirrored so an external CRM can see
  # the full lead activity: conversations and their messages (WhatsApp replies,
  # private notes, and the management snapshot stored in content_attributes), and
  # users (agents) so activity can be attributed to a named agent — WITHOUT any
  # credential columns (those are stripped, see EXCLUDED_COLUMNS_BY_MODEL + the
  # sensitive-name patterns). Conversation/Message carry account_id; User is
  # scoped per account through account_users (see MODELS_WITHOUT_ACCOUNT_ID).
  EXTRA_MODELS = %w[Conversation Message User Note].freeze

  # Models exported even though they lack a direct account_id column: the account
  # is reached through an association. Value is a lambda returning the per-account
  # scope. Used for multi-row custom tables (Asesorías, Casos…) whose rows link to
  # a lead but only know their account through jabvox_custom_table.
  MODELS_WITHOUT_ACCOUNT_ID = {
    'JabvoxCustomTableRow' => lambda { |account_id|
      JabvoxCustomTableRow.joins(:jabvox_custom_table)
                          .where(jabvox_custom_tables: { account_id: account_id })
    },
    # The COLUMN definitions (names/labels/types/options) of the custom tables,
    # reached through jabvox_custom_table. Without them the exported rows have no
    # column names/labels — the schema of the multi-row tables would be lost.
    'JabvoxCustomColumn' => lambda { |account_id|
      JabvoxCustomColumn.joins(:jabvox_custom_table)
                        .where(jabvox_custom_tables: { account_id: account_id })
    },
    # Only users that belong to THIS account (via account_users) — never the whole
    # users table. Uses a distinct id sub-select (NOT SELECT DISTINCT users.*,
    # which fails: User has json columns with no equality operator).
    'User' => lambda { |account_id|
      user_ids = AccountUser.where(account_id: account_id).select(:user_id)
      User.where(id: user_ids)
    }
  }.freeze

  # Maps a model to the account feature flag that must be enabled for it to be
  # exported. Keyed by exact model name first, then by name prefix. Models with
  # no entry here are always exported when the module gating runs (they are core
  # lead/contact/config data not tied to an optional module).
  MODULE_BY_PREFIX = {
    'JabvoxDialer' => 'jabvox_dialer',
    'JabvoxKanban' => 'jabvox_kanban',
    'JabvoxProduct' => 'jabvox_products',
    'JabvoxOrder' => 'jabvox_products',
    'JabvoxCurrency' => 'jabvox_products',
    'JabvoxDiscount' => 'jabvox_products',
    'JabvoxTaxRate' => 'jabvox_products',
    'JabvoxItemType' => 'jabvox_products',
    'JabvoxUnitOfMeasure' => 'jabvox_products',
    'JabvoxSalesReport' => 'jabvox_products',
    'JabvoxSms' => 'jabvox_sms',
    'JabvoxAiChat' => 'jabvox_ai_chat',
    'JabvoxAudio' => 'jabvox_audio_analysis',
    'JabvoxCdr' => 'jabvox_cdr',
    'JabvoxAffiliate' => 'jabvox_affiliates',
    'JabvoxCalendar' => 'jabvox_calendar',
    'JabvoxInternal' => 'jabvox_internal_chat',
    'JabvoxResponseBot' => 'jabvox_response_bot',
    'JabvoxEmail' => 'jabvox_email',
    'JabvoxForm' => 'jabvox_forms',
    'JabvoxWhatsappTemplate' => 'jabvox_whatsapp_templates',
    'JabvoxBulkWhatsapp' => 'jabvox_bulk_whatsapp',
    # NOTE: management states/answers are core lead activity (no *_enabled_jabvox
    # toggle), so they are intentionally NOT gated here — always exported.
    'JabvoxTask' => 'jabvox_tasks',
    'JabvoxAnalytics' => 'jabvox_analytics',
    'JabvoxCallLog' => 'jabvox_click_to_call'
  }.freeze

  # Customer-facing export groups: a friendly layer over the technical models, so
  # the customer picks "Conversations / WhatsApp", "Calls", "Advisories", etc.
  # instead of raw table names. Each group lists the model-name prefixes it owns
  # and (optionally) the account feature that must be enabled for it to appear.
  #
  # `always` groups are core lead activity and are always offered/selected.
  # The `core` group is implicit and never toggled off (leads, contacts,
  # campaigns, typifications, custom tables…): it's what everything else joins to.
  EXPORT_GROUPS = [
    { key: 'core', always: true, models: %w[JabvoxLead JabvoxCampaign JabvoxTypification
                                             JabvoxManagementState JabvoxManagementQuestion
                                             JabvoxManagementAnswer JabvoxCustomTable User] },
    { key: 'conversations', always: true, models: %w[Conversation Message Note] },
    { key: 'calls', feature: 'jabvox_click_to_call', models: %w[JabvoxCallLog] },
    { key: 'dialer', feature: 'jabvox_dialer', models: %w[JabvoxDialer] },
    { key: 'custom_tables', always: true, models: %w[JabvoxCustomTableRow JabvoxCustomColumn] },
    { key: 'kanban', feature: 'jabvox_kanban', models: %w[JabvoxKanban] },
    { key: 'tasks', feature: 'jabvox_tasks', models: %w[JabvoxTask] },
    { key: 'products', feature: 'jabvox_products', models: %w[JabvoxProduct JabvoxOrder JabvoxCurrency
                                                              JabvoxDiscount JabvoxTaxRate JabvoxItemType
                                                              JabvoxUnitOfMeasure JabvoxSalesReport] },
    { key: 'sms', feature: 'jabvox_sms', models: %w[JabvoxSms] },
    { key: 'email', feature: 'jabvox_email', models: %w[JabvoxEmail] },
    { key: 'calendar', feature: 'jabvox_calendar', models: %w[JabvoxCalendar] },
    { key: 'affiliates', feature: 'jabvox_affiliates', models: %w[JabvoxAffiliate] },
    { key: 'cdr', feature: 'jabvox_cdr', models: %w[JabvoxCdr] },
    { key: 'forms', feature: 'jabvox_forms', models: %w[JabvoxForm] },
    { key: 'whatsapp_templates', feature: 'jabvox_whatsapp_templates', models: %w[JabvoxWhatsappTemplate] },
    { key: 'bulk_whatsapp', feature: 'jabvox_bulk_whatsapp', models: %w[JabvoxBulkWhatsapp] },
    { key: 'ai_chat', feature: 'jabvox_ai_chat', models: %w[JabvoxAiChat] },
    { key: 'audio', feature: 'jabvox_audio_analysis', models: %w[JabvoxAudio] },
    { key: 'internal_chat', feature: 'jabvox_internal_chat', models: %w[JabvoxInternal] },
    { key: 'response_bot', feature: 'jabvox_response_bot', models: %w[JabvoxResponseBot] },
    { key: 'analytics', feature: 'jabvox_analytics', models: %w[JabvoxAnalytics] }
  ].freeze

  # The export groups available to an account: the ones whose feature is enabled
  # (or that are `always`). Each entry: { key:, always:, table_count: }. Used by
  # the settings UI so the customer only sees groups relevant to their plan.
  def available_groups(account)
    models = exportable_models(account)
    EXPORT_GROUPS.filter_map do |group|
      next if group[:feature] && !feature_on?(account, group[:feature])

      count = models.count { |m| group_owns?(group, m.name) }
      next if count.zero? && !group[:always]

      { key: group[:key], always: group[:always] == true, table_count: count }
    end
  end

  # A jabvox model is exportable when it's an ActiveRecord model, has an account_id,
  # is not in the exclusion list, and is not an encrypted-credentials model.
  #
  # When `account` is given, the set is further restricted to the modules that
  # account has enabled (so a customer without the dialer never gets dialer
  # tables), and always keeps the module-agnostic core (leads, contacts,
  # conversations, messages, campaigns, custom tables, typifications…).
  #
  # `selected_groups` (array of group keys) further narrows to what the customer
  # chose in the settings screen; nil/empty means "everything enabled".
  #
  # We only memoize the base scan once the app is fully booted (all models
  # eager-loaded). During boot the model set may be incomplete, so we never cache
  # a partial result — otherwise a process could permanently miss models that
  # hadn't loaded yet when the initializer ran.
  def exportable_models(account = nil, selected_groups: nil)
    base = base_exportable_models
    return base if account.nil?

    models = base.select { |model| module_enabled_for?(model, account) }
    return models if selected_groups.nil? || selected_groups.empty?

    keep = selected_group_set(selected_groups)
    models.select { |model| model_in_groups?(model.name, keep) }
  end

  # Resolves the set of group keys to actually honor: the customer's selection
  # plus the always-on groups (core, conversations, custom_tables) which are never
  # excludable (everything joins to them).
  def selected_group_set(selected_groups)
    always = EXPORT_GROUPS.select { |g| g[:always] }.map { |g| g[:key] }
    (Array(selected_groups).map(&:to_s) + always).uniq
  end

  def model_in_groups?(model_name, group_keys)
    EXPORT_GROUPS.any? do |group|
      group_keys.include?(group[:key]) && group_owns?(group, model_name)
    end
  end

  def group_owns?(group, model_name)
    group[:models].any? { |prefix| model_name == prefix || model_name.start_with?(prefix) }
  end

  def feature_on?(account, feature)
    account.feature_enabled?(feature)
  rescue StandardError
    false
  end

  def base_exportable_models
    return @exportable_models if @exportable_models

    models = discover_models
    @exportable_models = models if Rails.application.initialized?
    models
  end

  # True when the model's owning module is enabled for the account (or the model
  # isn't tied to any optional module).
  def module_enabled_for?(model, account)
    flag = module_flag_for(model.name)
    return true if flag.nil?

    account.feature_enabled?(flag)
  rescue StandardError => e
    # If the flag can't be resolved (e.g. a module with no *_enabled_jabvox
    # column), fail OPEN and include the model — the gate is a convenience, not a
    # security wall (sensitive columns are already stripped by safe_columns).
    Rails.logger.warn("[ExternalExport::Catalog] module gate for #{model.name} (#{flag}): #{e.class}")
    true
  end

  # The feature flag governing a model, by exact name then longest matching prefix.
  def module_flag_for(model_name)
    matches = MODULE_BY_PREFIX.select { |prefix, _| model_name.start_with?(prefix) }
    return nil if matches.empty?

    # Longest prefix wins (e.g. JabvoxCallLog over a hypothetical JabvoxCall).
    matches.max_by { |prefix, _| prefix.length }.last
  end

  # Force a re-scan (used right after the boot hook wires up the models).
  def reset!
    @exportable_models = nil
  end

  # Per-account scope for a model: by account_id column when present, otherwise via
  # the association scope declared in MODELS_WITHOUT_ACCOUNT_ID.
  def account_scope(model, account_id)
    special = MODELS_WITHOUT_ACCOUNT_ID[model.name]
    return special.call(account_id) if special

    model.where(account_id: account_id)
  end

  # Safe columns for a model = its DB columns minus the sensitive ones (by name
  # pattern) and any model-specific excluded columns (sensitive JSON blobs).
  #
  # Uses base_class so STI subclasses (e.g. SuperAdmin/AgentBot < User) inherit
  # the parent's exclusion list — otherwise a subclass would leak the very
  # credential columns we strip from the base.
  def safe_columns(model)
    excluded = EXCLUDED_COLUMNS_BY_MODEL[base_name(model)] || []
    model.column_names.reject { |c| sensitive?(c) || excluded.include?(c) }
  end

  # The STI base-class name (e.g. SuperAdmin -> "User"), or the model's own name.
  def base_name(model)
    model.respond_to?(:base_class) ? model.base_class.name : model.name
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
    jabvox = ObjectSpace.each_object(Class).select do |klass|
      klass < ActiveRecord::Base &&
        klass.name.to_s.start_with?('Jabvox') &&
        klass.name.to_s.exclude?('::') &&
        EXCLUDED_MODELS.exclude?(klass.name) &&
        table_exists_with_account?(klass)
    rescue StandardError
      false
    end
    (jabvox + extra_models).uniq(&:name).sort_by(&:name)
  end

  # Core (non-Jabvox) models we explicitly mirror for CRM sync — resolved by name
  # so a typo or a removed model never blows up the scan. Includes both models that
  # carry account_id (EXTRA_MODELS) and ones reached through an association
  # (MODELS_WITHOUT_ACCOUNT_ID).
  def extra_models
    # These are an explicitly curated allowlist with per-model column filtering
    # (EXCLUDED_COLUMNS_BY_MODEL + sensitive patterns), so the "encrypted =
    # credential store" auto-exclusion (meant for the Jabvox* auto-scan) does NOT
    # apply here — e.g. User has an encrypted Devise column but is safe to export
    # once its credential columns are stripped.
    (EXTRA_MODELS + MODELS_WITHOUT_ACCOUNT_ID.keys).filter_map do |name|
      klass = name.safe_constantize
      next unless klass && klass < ActiveRecord::Base
      next unless klass.table_exists?

      # account_id models must actually have the column; association-scoped ones
      # are exempt from that requirement.
      if MODELS_WITHOUT_ACCOUNT_ID.key?(name)
        klass
      elsif klass.column_names.include?('account_id')
        klass
      end
    end
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
