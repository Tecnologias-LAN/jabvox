# Per-user dashboard access: which dashboards a single user is allowed to see.
# Backed by JabvoxAnalyticsShare rows (subject_type 'user', access_level 'view');
# this is the same mechanism the per-dashboard Share dialog uses, exposed here
# as a user-centric view so an admin can grant a user access to several
# dashboards at once ("this user only sees these 3").
#
# Note: account administrators and users whose analytics role grants
# `view_all_data` always see every dashboard regardless of these grants — the
# index surfaces that via `sees_all` so the UI can explain it.
class Api::V1::Accounts::Jabvox::Analytics::UserDashboardAccessController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :ensure_admin

  # GET user_dashboard_access?user_id=:id
  # Lists every dashboard in the account with a `has_access` flag for the user.
  def show
    user = account_user!
    granted = granted_dashboard_ids(user.user_id)

    render json: {
      user_id: user.user_id,
      sees_all: sees_all?(user),
      dashboards: dashboards.map do |d|
        {
          id: d.id,
          name_jabvox: d.name_jabvox,
          has_access: d.created_by_id == user.user_id || granted.include?(d.id)
        }
      end
    }
  end

  # PATCH user_dashboard_access { user_id:, dashboard_ids: [] }
  # Syncs the user's 'view' shares to exactly the given dashboards (excluding
  # dashboards they own, which are always accessible and never get a share row).
  def update
    user = account_user!
    target_ids = Array(params[:dashboard_ids]).map(&:to_i)
    owned_ids = dashboards.where(created_by_id: user.user_id).pluck(:id)
    desired = valid_dashboard_ids(target_ids) - owned_ids

    sync_shares(user.user_id, desired)
    audit!(action: 'permission.change', metadata: { user_id: user.user_id, dashboard_ids: desired })
    show
  end

  private

  def dashboards
    @dashboards ||= Current.account.jabvox_analytics_dashboards.order(:name_jabvox)
  end

  # Restricts the requested ids to dashboards that actually belong to the account.
  def valid_dashboard_ids(ids)
    dashboards.where(id: ids).pluck(:id)
  end

  def account_user!
    Current.account.account_users.find_by!(user_id: params[:user_id])
  end

  def granted_dashboard_ids(user_id)
    JabvoxAnalyticsShare.where(
      account_id: Current.account.id, subject_type_jabvox: 'user', subject_id_jabvox: user_id
    ).pluck(:dashboard_id)
  end

  def sees_all?(account_user)
    account_user.administrator? ||
      Jabvox::Analytics::PermissionResolver.new(account_user.user, Current.account).view_all_data?
  end

  # Adds share rows for newly-granted dashboards and removes rows no longer desired.
  def sync_shares(user_id, desired_ids)
    scope = JabvoxAnalyticsShare.where(
      account_id: Current.account.id, subject_type_jabvox: 'user', subject_id_jabvox: user_id
    )
    existing_ids = scope.pluck(:dashboard_id)

    scope.where(dashboard_id: existing_ids - desired_ids).destroy_all

    (desired_ids - existing_ids).each do |dashboard_id|
      JabvoxAnalyticsShare.create!(
        account_id: Current.account.id,
        dashboard_id: dashboard_id,
        subject_type_jabvox: 'user',
        subject_id_jabvox: user_id,
        access_level_jabvox: 'view',
        created_by_id: current_user.id
      )
    end
  end
end
