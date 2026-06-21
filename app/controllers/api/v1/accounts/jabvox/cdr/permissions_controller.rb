class Api::V1::Accounts::Jabvox::Cdr::PermissionsController < Api::V1::Accounts::Jabvox::Cdr::BaseController
  before_action :ensure_admin

  # GET /permissions — every account user with their current can_view flag.
  def index
    granted = Current.account.jabvox_cdr_report_permissions.where(can_view: true).pluck(:user_id).to_set
    users = Current.account.users.select(:id, :name, :email)
    render json: {
      permissions: users.map do |user|
        { user_id: user.id, name: user.name, email: user.email, can_view: granted.include?(user.id) }
      end
    }
  end

  # PATCH /permissions/bulk — replace the set of users allowed to view reports.
  def bulk
    user_ids = Array(params[:user_ids]).map(&:to_i)
    valid_ids = Current.account.users.where(id: user_ids).pluck(:id)

    ActiveRecord::Base.transaction do
      Current.account.jabvox_cdr_report_permissions.where.not(user_id: valid_ids).update_all(can_view: false)
      valid_ids.each do |uid|
        perm = Current.account.jabvox_cdr_report_permissions.find_or_initialize_by(user_id: uid)
        perm.update!(can_view: true)
      end
    end
    head :no_content
  end
end
