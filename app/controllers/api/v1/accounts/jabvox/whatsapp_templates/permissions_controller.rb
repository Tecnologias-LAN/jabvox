class Api::V1::Accounts::Jabvox::WhatsappTemplates::PermissionsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin

  def index
    granted = Current.account.jabvox_whatsapp_template_permissions.where(can_manage: true).pluck(:user_id).to_set
    users = Current.account.users.select(:id, :name, :email)
    render json: {
      permissions: users.map do |u|
        { user_id: u.id, name: u.name, email: u.email, can_manage: granted.include?(u.id) }
      end
    }
  end

  def bulk
    user_ids = Array(params[:user_ids]).map(&:to_i)
    valid_ids = Current.account.users.where(id: user_ids).pluck(:id)
    ActiveRecord::Base.transaction do
      Current.account.jabvox_whatsapp_template_permissions # rubocop:disable Rails/SkipsModelValidations
                     .where.not(user_id: valid_ids).update_all(can_manage: false)
      valid_ids.each do |uid|
        perm = Current.account.jabvox_whatsapp_template_permissions.find_or_initialize_by(user_id: uid)
        perm.update!(can_manage: true)
      end
    end
    head :no_content
  end
end
