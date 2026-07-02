# Resolves a user's effective Analytics capabilities within an account.
#
# Precedence (highest first):
#   1. Account administrators get ALL permissions automatically (required by spec).
#   2. Per-user overrides (jabvox_analytics_user_permissions.overrides_jabvox).
#   3. The user's assigned role grants.
#   4. Otherwise no access.
#
#   resolver = Jabvox::Analytics::PermissionResolver.new(user, account)
#   resolver.can?(:create)               #=> true/false
#   resolver.scope_for(Dashboard.all)    #=> relation filtered to what the user may see
class Jabvox::Analytics::PermissionResolver
  def initialize(user, account)
    @user = user
    @account = account
  end

  def admin?
    @admin ||= account_user&.administrator? || false
  end

  def can?(key)
    key = key.to_s
    return true if admin?

    capabilities.fetch(key, false)
  end

  # The full capability hash (permission_key => boolean), for serializing to the UI.
  def capabilities
    @capabilities ||= build_capabilities
  end

  def can_access?
    admin? || can?(:access)
  end

  def view_all_data?
    can?(:view_all_data)
  end

  # Whether the user may query a specific data source.
  def can_access_data_source?(data_source)
    return true if admin?
    return false unless can?(:access)

    JabvoxAnalyticsDataSourcePermission
      .where(account_id: @account.id, data_source_id: data_source.id, can_query_jabvox: true)
      .where(subject_scope)
      .exists?
  end

  def can_use_custom_sql_on?(data_source)
    return true if admin?
    return false unless can?(:use_custom_sql)

    JabvoxAnalyticsDataSourcePermission
      .where(account_id: @account.id, data_source_id: data_source.id, can_use_custom_sql_jabvox: true)
      .where(subject_scope)
      .exists?
  end

  # Narrow an owned-resource relation to what the user may see/act on.
  # Admins and users with view_all_data see everything; others see only their own
  # plus dashboards explicitly shared with them.
  def scope_for(relation)
    return relation if admin? || view_all_data?

    if relation.klass == JabvoxAnalyticsDashboard
      relation.where(created_by_id: @user.id).or(relation.where(id: shared_dashboard_ids))
    else
      relation.where(created_by_id: @user.id)
    end
  end

  private

  def build_capabilities
    # Custom-role grants form the base layer: a role granting jabvox_analytics_access
    # gives entry access; jabvox_analytics_manage grants the management capabilities.
    # Analytics' own role/overrides (finer-grained) merge on top, so nothing is lost.
    caps = custom_role_capabilities
    caps = caps.merge(role.grants) if role&.grants.present?
    caps = caps.merge(overrides) if overrides.present?
    caps.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
  end

  # Maps the two Jabvox custom-role analytics permissions onto Analytics'
  # capability keys. Only turns capabilities ON (never off), so it can only
  # widen access from the custom role, never remove Analytics-native grants.
  def custom_role_capabilities
    role = account_user&.custom_role
    return {} if role.nil?

    caps = {}
    caps['access'] = true if role.grants?('jabvox_analytics_access')
    if role.grants?('jabvox_analytics_manage')
      %w[access create edit_own edit_all delete_own delete_all share
         view_all_data manage_data_sources].each { |k| caps[k] = true }
    end
    caps
  end

  def user_permission
    @user_permission ||= JabvoxAnalyticsUserPermission.find_by(account_id: @account.id, user_id: @user.id)
  end

  def role
    @role ||= user_permission&.role
  end

  def overrides
    @overrides ||= (user_permission&.overrides_jabvox || {}).stringify_keys
  end

  def account_user
    @account_user ||= @account.account_users.find_by(user_id: @user.id)
  end

  # Matches data-source permission rows granted to the user directly or via their role.
  def subject_scope
    ['user_id = :uid OR role_id = :rid', { uid: @user.id, rid: role&.id }]
  end

  def shared_dashboard_ids
    subject_clauses = [['user', @user.id]]
    subject_clauses << ['role', role.id] if role
    team_ids = @user.teams.where(account_id: @account.id).pluck(:id)
    team_ids.each { |tid| subject_clauses << ['team', tid] }

    scope = JabvoxAnalyticsShare.where(account_id: @account.id).none
    subject_clauses.each do |type, sid|
      scope = scope.or(JabvoxAnalyticsShare.where(account_id: @account.id, subject_type_jabvox: type, subject_id_jabvox: sid))
    end
    scope.pluck(:dashboard_id)
  end
end
