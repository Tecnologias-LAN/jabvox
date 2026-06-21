# Resolves a user's effective access level to a dashboard, considering ownership, admin
# status, and shares granted to the user / their analytics role / their teams.
#
#   Jabvox::Analytics::ShareService.new(dashboard, user, account).access_level
#   #=> nil | 'view' | 'edit' | 'admin'
class Jabvox::Analytics::ShareService
  def initialize(dashboard, user, account)
    @dashboard = dashboard
    @user = user
    @account = account
  end

  def access_level
    return 'admin' if owner? || admin?

    best_shared_level
  end

  def can_view?
    access_level.present?
  end

  def can_edit?
    %w[edit admin].include?(access_level)
  end

  def can_admin?
    access_level == 'admin'
  end

  private

  def owner?
    @dashboard.created_by_id == @user.id
  end

  def admin?
    @account.account_users.find_by(user_id: @user.id)&.administrator? || false
  end

  def best_shared_level
    levels = matching_shares.map(&:rank)
    return nil if levels.empty?

    JabvoxAnalyticsShare::ACCESS_RANK.key(levels.max)
  end

  def matching_shares
    role_id = JabvoxAnalyticsUserPermission.where(account_id: @account.id, user_id: @user.id).pick(:role_id)
    team_ids = @user.teams.where(account_id: @account.id).pluck(:id)

    subjects = [['user', @user.id]]
    subjects << ['role', role_id] if role_id
    team_ids.each { |tid| subjects << ['team', tid] }

    scope = JabvoxAnalyticsShare.where(account_id: @account.id, dashboard_id: @dashboard.id).none
    subjects.each do |type, sid|
      scope = scope.or(
        JabvoxAnalyticsShare.where(account_id: @account.id, dashboard_id: @dashboard.id,
                                   subject_type_jabvox: type, subject_id_jabvox: sid)
      )
    end
    scope
  end
end
