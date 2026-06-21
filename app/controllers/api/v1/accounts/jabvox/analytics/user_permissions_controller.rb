# The user x capability matrix: assigns each user an analytics role plus granular overrides.
class Api::V1::Accounts::Jabvox::Analytics::UserPermissionsController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :ensure_admin

  def index
    account_users = Current.account.account_users.includes(:user)
    assignments = JabvoxAnalyticsUserPermission.where(account_id: Current.account.id).index_by(&:user_id)
    roles = Current.account.jabvox_analytics_roles.order(:name_jabvox)

    render json: {
      keys: JabvoxAnalyticsPermission::KEYS,
      roles: roles.map { |r| { id: r.id, name_jabvox: r.name_jabvox, slug_jabvox: r.slug_jabvox } },
      users: account_users.map { |au| serialize_user(au, assignments[au.user_id]) }
    }
  end

  def create
    upsert
  end

  def update
    upsert
  end

  def destroy
    JabvoxAnalyticsUserPermission.where(account_id: Current.account.id, user_id: params[:id]).destroy_all
    head :no_content
  end

  # PATCH user_permissions/bulk { assignments: [{ user_id:, role_id:, overrides: {} }] }
  def bulk
    Array(params[:assignments]).each do |entry|
      e = entry.permit(:user_id, :role_id, overrides: {}).to_h
      assign(e['user_id'], e['role_id'], e['overrides'] || {})
    end
    audit!(action: 'permission.change', metadata: { bulk: true, count: Array(params[:assignments]).size })
    head :no_content
  end

  private

  def upsert
    e = params.require(:user_permission).permit(:user_id, :role_id, overrides: {}).to_h
    record = assign(e['user_id'], e['role_id'], e['overrides'] || {})
    audit!(action: 'permission.change', metadata: { user_id: e['user_id'], role_id: e['role_id'] })
    render json: { user_id: record.user_id, role_id: record.role_id, overrides: record.overrides_jabvox }
  end

  def assign(user_id, role_id, overrides)
    record = JabvoxAnalyticsUserPermission.find_or_initialize_by(account_id: Current.account.id, user_id: user_id)
    record.role_id = role_id
    record.overrides_jabvox = overrides.slice(*JabvoxAnalyticsPermission::KEYS)
    record.save!
    record
  end

  def serialize_user(account_user, assignment)
    resolver = Jabvox::Analytics::PermissionResolver.new(account_user.user, Current.account)
    {
      user_id: account_user.user_id,
      name: account_user.user.name,
      email: account_user.user.email,
      is_account_admin: account_user.administrator?,
      role_id: assignment&.role_id,
      overrides: assignment&.overrides_jabvox || {},
      effective: JabvoxAnalyticsPermission::KEYS.index_with { |k| resolver.can?(k) }
    }
  end
end
