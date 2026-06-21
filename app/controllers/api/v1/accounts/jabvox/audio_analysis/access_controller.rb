class Api::V1::Accounts::Jabvox::AudioAnalysis::AccessController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_admin

  # GET /access/users — every account user with their two permission flags.
  def users
    perms = Current.account.jabvox_audio_permissions.index_by(&:user_id)
    list = Current.account.users.select(:id, :name, :email).map do |user|
      perm = perms[user.id]
      {
        user_id: user.id, name: user.name, email: user.email,
        can_access: perm&.can_access || false,
        can_view_reports: perm&.can_view_reports || false
      }
    end
    render json: { users: list }
  end

  # POST /access/users — upsert a single user's permissions.
  def update_users
    user = Current.account.users.find_by(id: params[:user_id])
    return render(json: { error: 'Usuario no encontrado' }, status: :not_found) unless user

    perm = Current.account.jabvox_audio_permissions.find_or_initialize_by(user_id: user.id)
    perm.update!(
      can_access: ActiveModel::Type::Boolean.new.cast(params[:can_access]),
      can_view_reports: ActiveModel::Type::Boolean.new.cast(params[:can_view_reports])
    )
    head :no_content
  end
end
