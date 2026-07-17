# Syncs the account's existing records to the external DB, in low-impact batches.
#
# Two uses:
#   - initial backfill (since: nil)  -> every record of every exportable model.
#   - periodic reconcile (since: ts) -> only records changed after `since`
#     (updated_at > since), catching anything the real-time after_commit mirror
#     missed (job failures, downtime, etc.).
#
# Runs on a low-priority queue and iterates with find_each(batch_size:) so it
# never loads a whole table into memory or blocks user-facing work. One bad row
# never aborts the run; per-row errors are counted and capped in the log.
class Jabvox::ExternalExport::BackfillService
  BATCH_SIZE = 500
  MAX_LOGGED_ERRORS = 50

  def initialize(target)
    @target = target
    @account = target.account
    # Preload the contact->lead map ONCE so derived link columns (jabvox_lead_id
    # on conversations/messages/dialer calls) are hash lookups, not a query per row.
    resolver = Jabvox::ExternalExport::DerivedColumns::LeadResolver.preloaded(@account.id)
    @exporter = Jabvox::ExternalExport::RowExporterService.new(target, resolver: resolver)
    @adapter = Jabvox::ExternalExport::WriteAdapter.new(target)
  end

  # since: a Time to only export records updated after it, or nil for everything.
  # Returns counters { exported:, failed:, at: }.
  def call(since: nil)
    guard!
    @exported = 0
    @failed = 0
    @logged = 0

    # ONE remote connection for the WHOLE backfill (not one per model): opening a
    # connection to a remote DB costs a full network handshake (~200ms), and with
    # ~80 models that dominated the runtime. Reusing a single connection keeps the
    # backfill fast even with many small models.
    @adapter.with_connection do |client|
      models = Jabvox::ExternalExport::Catalog.exportable_models(
        @account, selected_groups: @target.selected_modules
      )
      models.each do |model|
        scope = incremental_scope(model, since)
        next if scope.nil? || !scope.exists?

        export_model(client, model, scope)
      end
    end

    { exported: @exported, failed: @failed, at: Time.current.iso8601 }
  end

  private

  # Scope for this model given the watermark. Full backfill (since nil) = all rows.
  # Incremental = rows changed after `since`, using updated_at, or created_at for
  # append-only models that lack updated_at (so they aren't re-sent every 5 min).
  # Eager-loads the lead↔source link to avoid an N+1 when building correlation ids.
  def incremental_scope(model, since)
    # Account scope handles models without a direct account_id (reached via an
    # association, e.g. custom table rows).
    scope = Jabvox::ExternalExport::Catalog.account_scope(model, @account.id)
    scope = scope.includes(:jabvox_lead_source_records) if model == JabvoxLead
    # Derived link columns walk associations; eager-load them to avoid N+1 over
    # potentially huge message/call volumes during backfill.
    scope = scope.includes(:conversation) if model == Message
    scope = scope.includes(:jabvox_dialer_campaign_contact) if model == JabvoxDialerCallLog
    scope = scope.includes(:contact) if model == Note
    return scope unless since

    watermark = %w[updated_at created_at].find { |c| model.column_names.include?(c) }
    # No timestamp column → can't tell what changed. The real-time after_commit
    # mirror already covers these; skip them in incremental runs (they're only
    # sent in the initial full backfill) instead of re-sending everything.
    return nil unless watermark

    scope.where("#{model.table_name}.#{watermark} > ?", since)
  end

  # ONE connection reused for the whole model, writing MULTI-ROW upserts per batch.
  # Over a remote DB this is ~100x fewer round-trips than row-by-row — seconds vs
  # many minutes. Rows are grouped by (columns, key) so each group is one INSERT.
  #
  # A write error scoped to THIS model (e.g. a type mismatch on the customer side)
  # is logged and the model is skipped — it must not abort the whole backfill. A
  # genuine connection failure (DB unreachable) still aborts, so the scheduler
  # retries later instead of hammering.
  def export_model(client, model, scope)
    scope.in_batches(of: BATCH_SIZE) do |relation|
      plans = relation.filter_map { |record| build_plan(model, record) }
      flush(client, plans)
    end
  rescue Jabvox::ExternalExport::WriteAdapter::ConnectionError => e
    raise if connection_level?(e) # DB unreachable → abort; else treat as model-level.

    record_model_failure(model, e)
  rescue StandardError => e
    record_model_failure(model, e)
  end

  # A message that looks like a connect/timeout failure (vs. a per-write data error).
  def connection_level?(error)
    error.message.to_s.match?(/could not connect|timeout|Connection refused|server closed|no pg_hba|authentication failed|Unknown database|Access denied/i)
  end

  def record_model_failure(model, error)
    @failed += 1
    Rails.logger.error("[ExternalExport::Backfill] model #{model.name} skipped: #{error.class}: #{error.message}")
    # Surface the model-level failure in the history so the customer sees it.
    JabvoxExportSyncLog.record!(
      target: @target, model_name: model.name, record_id: 0,
      status: 'failed', operation: 'backfill', error: "#{model.name}: #{error.message}"
    )
  end

  # Builds a row plan, counting/logging (capped) any per-record failure as skipped.
  def build_plan(model, record)
    @exporter.plan_for(record)
  rescue StandardError => e
    @failed += 1
    if @logged < MAX_LOGGED_ERRORS
      Rails.logger.error("[ExternalExport::Backfill] #{model.name}##{record.id}: #{e.class}")
      @logged += 1
    end
    JabvoxExportSyncLog.record!(
      target: @target, model_name: model.name, record_id: record.id,
      status: 'failed', operation: 'backfill', error: e.message
    )
    nil
  end

  # Groups plans by (columns, key) and writes each group as one multi-row upsert.
  def flush(client, plans)
    plans.group_by { |p| [p[:table], p[:values].keys, p[:key]] }.each do |(table, cols, key), group|
      rows = group.map { |p| p[:values] }
      @adapter.upsert_batch_on(client, table, cols, rows, conflict_key: key)
      @exported += rows.size
    end
  end

  def guard!
    Jabvox::ExternalExport.guard!(@target)
  end
end
