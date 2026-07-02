# Keeps Audio Analysis and AI Chat storages mirrored for an account.
#
# Both modules use structurally-identical storage buckets, but each lives in its
# own table. The product requirement is that a storage exists in BOTH modules
# and stays a permanent mirror: create / edit / delete on one side propagates to
# the other, matched by name within the account. When the second module is
# enabled, the first module's storages are copied over (backfill).
#
# This mirrors the design of Jabvox::PipelineSyncService.
#
# Design notes / safety:
#   - Mirroring only happens when BOTH modules are enabled for the account.
#   - A thread-local reentrancy guard prevents the infinite mirror loop.
#   - Matching is by (account_id, name). Renaming is create+delete of the mirror.
#   - Audio storages with use_documents_config = true are NOT mirrored: they have
#     no own credentials (they reuse the AI Chat config), so mirroring them would
#     produce an empty, useless AI Chat storage.
class Jabvox::StorageSyncService
  # Columns copied verbatim between the two storage tables.
  SHARED_ATTRS = %w[name bucket_name bucket_region endpoint access_key secret_key path_prefix].freeze

  class << self
    def syncing?
      Thread.current[:jabvox_storage_syncing] == true
    end

    def with_guard
      return if syncing?

      Thread.current[:jabvox_storage_syncing] = true
      begin
        yield
      ensure
        Thread.current[:jabvox_storage_syncing] = false
      end
    end

    def both_modules_enabled?(account)
      account.jabvox_audio_analysis_enabled_jabvox? && account.jabvox_ai_chat_enabled_jabvox?
    end

    # Upsert the mirror of `source` into the other module's table.
    def mirror(source)
      return if skip_source?(source)

      with_guard do
        account = source.account
        next unless both_modules_enabled?(account)

        mirror_into(mirror_scope(account, source), source)
      end
    end

    # Remove the mirror of a destroyed storage from the other table.
    def remove_mirror(source)
      with_guard do
        account = source.account
        next unless both_modules_enabled?(account)

        mirror_scope(account, source).where(name: source.name).find_each(&:destroy)
      end
    end

    # Backfill both directions so each module has every storage the other has.
    # Called when a module is turned on. Idempotent (matches by name).
    def mirror_all(account)
      return unless both_modules_enabled?(account)

      with_guard do
        account.jabvox_audio_storages.where(use_documents_config: false).find_each do |audio|
          mirror_into(account.jabvox_ai_chat_storages, audio)
        end
        account.jabvox_ai_chat_storages.find_each do |ai|
          mirror_into(account.jabvox_audio_storages, ai)
        end
      end
    end

    private

    # Audio storages that reuse the documents config have no own credentials to
    # share, so they are never mirrored into AI Chat.
    def skip_source?(source)
      source.is_a?(JabvoxAudioStorage) && source.use_documents_config?
    end

    # The relation in the OTHER module for this source storage.
    def mirror_scope(account, source)
      source.is_a?(JabvoxAudioStorage) ? account.jabvox_ai_chat_storages : account.jabvox_audio_storages
    end

    def mirror_into(target_scope, source)
      target = target_scope.find_or_initialize_by(name: source.name)
      SHARED_ATTRS.each { |attr| assign_if_present(target, source, attr) }
      target.save! if target.changed?
    end

    def assign_if_present(target, source, attr)
      return unless target.respond_to?("#{attr}=") && source.respond_to?(attr)

      target.public_send("#{attr}=", source.public_send(attr))
    end
  end
end
