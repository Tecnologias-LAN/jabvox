# Keeps CDR and Audio Analysis pipelines mirrored for an account.
#
# Both modules use structurally-identical pipelines (same columns + stages),
# but each lives in its own table and drives its own analysis engine. The
# product requirement is that a pipeline exists in BOTH modules and stays a
# permanent mirror: create / edit / delete on one side propagates to the other,
# matched by name within the account. When the second module is enabled, the
# first module's pipelines are copied over.
#
# Design notes / safety:
#   - Mirroring only happens when BOTH modules are enabled for the account.
#     If only one is on, pipelines live only where they were created; enabling
#     the second module backfills them (see `mirror_all`).
#   - A thread-local reentrancy guard prevents the infinite loop that would
#     otherwise happen (A's after_commit writes B, whose after_commit writes A…).
#   - Matching is by (account_id, name). Renaming is treated as create+delete of
#     the mirror, which is the safe, predictable behavior for a name-keyed link.
#   - transcription_prompt is carried across (CDR now has the column too); CDR's
#     engine simply ignores it.
class Jabvox::PipelineSyncService
  # Columns copied verbatim between the two pipeline tables.
  SHARED_ATTRS = %w[
    name transcription_model_id typification_id is_default
    timestamp_mode_jabvox segment_seconds_jabvox transcription_prompt
  ].freeze
  STAGE_ATTRS = %w[name prompt llm_model_id position min_score].freeze

  class << self
    # Reentrancy guard: true while a sync write is in progress on this thread.
    def syncing?
      Thread.current[:jabvox_pipeline_syncing] == true
    end

    def with_guard
      return if syncing?

      Thread.current[:jabvox_pipeline_syncing] = true
      begin
        yield
      ensure
        Thread.current[:jabvox_pipeline_syncing] = false
      end
    end

    def both_modules_enabled?(account)
      account.jabvox_cdr_enabled_jabvox? && account.jabvox_audio_analysis_enabled_jabvox?
    end

    # Upsert the mirror of `source` into the other module's table.
    def mirror(source)
      with_guard do
        account = source.account
        next unless both_modules_enabled?(account)

        mirror_into(mirror_scope(account, source), source)
      end
    end

    # Remove the mirror of a destroyed pipeline from the other table.
    def remove_mirror(source)
      with_guard do
        account = source.account
        next unless both_modules_enabled?(account)

        mirror_scope(account, source).where(name: source.name).find_each(&:destroy)
      end
    end

    # Backfill both directions so each module has every pipeline the other
    # has. Called when a module is turned on. Idempotent (matches by name).
    def mirror_all(account)
      return unless both_modules_enabled?(account)

      with_guard do
        account.jabvox_cdr_pipelines.includes(:stages).find_each do |cdr|
          mirror_into(account.jabvox_audio_pipelines, cdr)
        end
        account.jabvox_audio_pipelines.includes(:stages).find_each do |audio|
          mirror_into(account.jabvox_cdr_pipelines, audio)
        end
      end
    end

    private

    # The relation in the OTHER module for this source pipeline.
    def mirror_scope(account, source)
      source.is_a?(JabvoxCdrPipeline) ? account.jabvox_audio_pipelines : account.jabvox_cdr_pipelines
    end

    # Find (by name) or build the mirror in target_scope and copy source into it.
    def mirror_into(target_scope, source)
      target = target_scope.find_or_initialize_by(name: source.name)
      copy_into(target, source)
    end

    # Copies shared attrs + stages from source into target and saves. Only
    # writes when something actually changed, to avoid churn.
    def copy_into(target, source)
      SHARED_ATTRS.each { |attr| assign_if_present(target, source, attr) }
      target.save! if target.changed?
      sync_stages(target, source)
    end

    # transcription_prompt exists on both tables now; guard anyway so the
    # service stays correct even if a column is missing in some environment.
    def assign_if_present(target, source, attr)
      return unless target.respond_to?("#{attr}=") && source.respond_to?(attr)

      target.public_send("#{attr}=", source.public_send(attr))
    end

    # Replace the target's stages with a copy of the source's stages, in order.
    # Rebuilt wholesale (small lists) so edits/removals mirror exactly.
    def sync_stages(target, source)
      desired = source.stages.order(:position).map do |stage|
        STAGE_ATTRS.index_with { |attr| stage.public_send(attr) }
      end
      current = target.stages.order(:position).map do |stage|
        STAGE_ATTRS.index_with { |attr| stage.public_send(attr) }
      end
      return if desired == current

      target.stages.destroy_all
      desired.each { |attrs| target.stages.create!(attrs) }
    end
  end
end
