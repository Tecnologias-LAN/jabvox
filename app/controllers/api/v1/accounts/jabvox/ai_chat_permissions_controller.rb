class Api::V1::Accounts::Jabvox::AiChatPermissionsController < Api::V1::Accounts::BaseController
  before_action :authorize_permissions

  def index
    users = Current.account.users.order(:name)
    perms = JabvoxAiChatUserPermission.where(account_id: Current.account.id).index_by(&:user_id)

    render json: users.map { |u|
      perm = perms[u.id]
      {
        user_id: u.id,
        name: u.name,
        email: u.email,
        can_use: perm ? perm.can_use_jabvox : true,
        can_use_models: perm ? perm.can_use_models_jabvox : true,
        can_use_documents: perm ? perm.can_use_documents_jabvox : true
      }
    }
  end

  def update
    perm = JabvoxAiChatUserPermission.find_or_initialize_by(account_id: Current.account.id, user_id: params[:user_id])
    perm.update!(permission_params)
    render json: { success: true }
  end

  def bulk_update
    params[:permissions].each do |user_perm|
      perm = JabvoxAiChatUserPermission.find_or_initialize_by(
        account_id: Current.account.id, user_id: user_perm[:user_id]
      )
      perm.update!(
        can_use_jabvox: user_perm[:can_use],
        can_use_models_jabvox: user_perm[:can_use_models],
        can_use_documents_jabvox: user_perm[:can_use_documents]
      )
    end
    head :ok
  end

  private

  def authorize_permissions
    authorize JabvoxAiChatUserPermission, policy_class: JabvoxAiChatPermissionPolicy
  end

  def permission_params
    params.require(:permission).permit(:can_use_jabvox, :can_use_models_jabvox, :can_use_documents_jabvox)
  end
end
