class MigrateModulePermissionsToCustomRoles < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  MIGRATED_ROLE_NAME = 'Permisos migrados'.freeze

  # Maps each legacy permission table to the custom-role capability keys it
  # should grant. `keys_for` receives a row and returns the keys implied by its
  # boolean flags. Missing tables are skipped so the migration is safe on any
  # environment (idempotent, data-optional).
  MODULES = [
    {
      table: 'jabvox_cdr_report_permissions',
      keys_for: ->(row) { row['can_view'] ? ['jabvox_cdr_view_reports'] : [] }
    },
    {
      table: 'jabvox_audio_permissions',
      keys_for: lambda do |row|
        keys = []
        keys << 'jabvox_audio_access' if row['can_access']
        keys << 'jabvox_audio_view_reports' if row['can_view_reports']
        keys
      end
    },
    {
      table: 'jabvox_ai_chat_user_permissions',
      keys_for: lambda do |row|
        keys = []
        keys << 'jabvox_ai_chat_use' if row['can_use_jabvox']
        keys << 'jabvox_ai_chat_manage' if row['can_use_models_jabvox'] || row['can_use_documents_jabvox']
        keys
      end
    },
    {
      table: 'jabvox_whatsapp_template_permissions',
      keys_for: ->(row) { row['can_manage'] ? ['jabvox_whatsapp_templates_manage'] : [] }
    }
  ].freeze

  def up
    # Accumulate, per (account_id, user_id), the union of capability keys implied
    # by every legacy permission row across all four modules.
    grants = Hash.new { |hash, key| hash[key] = [] }

    MODULES.each do |mod|
      next unless table_exists?(mod[:table])

      select_all("SELECT * FROM #{mod[:table]}").each do |row|
        keys = mod[:keys_for].call(row)
        next if keys.empty?

        grants[[row['account_id'].to_i, row['user_id'].to_i]].concat(keys)
      end
    end

    # Group by account so each account's migrated role is resolved once.
    grants.group_by { |(account_id, _user_id), _keys| account_id }.each do |account_id, entries|
      migrate_account(account_id, entries)
    end
  end

  # No-op: this is a forward data migration; we never revoke access on rollback.
  def down; end

  private

  def migrate_account(account_id, entries)
    return unless Account.exists?(id: account_id)

    account = Account.find(account_id)

    entries.each do |(_account_id, user_id), keys|
      account_user = account.account_users.find_by(user_id: user_id)
      # User no longer belongs to the account, or is an administrator (already
      # has every capability): nothing to migrate.
      next if account_user.nil? || account_user.administrator?

      ensure_grants(account, account_user, keys.uniq)
    end
  end

  # Ensures `account_user` has a custom role that includes every key in `keys`,
  # creating/reusing the account's migrated role when the user has none.
  def ensure_grants(account, account_user, keys)
    role = account_user.custom_role || migrated_role(account)
    merged = (Array(role.permissions) | keys)

    role.update!(permissions: merged) if merged.sort != Array(role.permissions).sort
    account_user.update!(custom_role_id: role.id) if account_user.custom_role_id != role.id
  end

  # Finds (or creates) the account-scoped "Permisos migrados" role. Reused across
  # users of the same account so re-running the migration never duplicates it.
  def migrated_role(account)
    account.custom_roles.find_or_create_by!(name: MIGRATED_ROLE_NAME) do |role|
      role.description = 'Rol generado automáticamente al migrar permisos de módulos Jabvox a Custom Roles.'
      role.permissions = []
    end
  end
end
