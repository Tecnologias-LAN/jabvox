# Idempotently creates the 4 system roles (admin/supervisor/analyst/viewer) and their default
# permission grants for an account. Safe to call repeatedly; called lazily on first access.
class Jabvox::Analytics::RoleSeeder
  def initialize(account)
    @account = account
  end

  def call
    JabvoxAnalyticsRole.system_role_defaults.each do |slug, attrs|
      role = JabvoxAnalyticsRole.find_or_create_by!(account: @account, slug_jabvox: slug) do |r|
        r.name_jabvox = attrs[:name]
        r.is_system_jabvox = true
      end
      sync_permissions(role, attrs[:permissions])
    end
  end

  private

  def sync_permissions(role, granted_keys)
    JabvoxAnalyticsPermission::KEYS.each do |key|
      perm = JabvoxAnalyticsPermission.find_or_initialize_by(
        account: @account, role: role, permission_key_jabvox: key
      )
      perm.granted_jabvox = granted_keys.include?(key)
      perm.save! if perm.changed?
    end
  end
end
