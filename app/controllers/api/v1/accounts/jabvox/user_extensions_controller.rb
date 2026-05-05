class Api::V1::Accounts::Jabvox::UserExtensionsController < Api::V1::Accounts::BaseController
  before_action :check_admin, only: [:index, :create, :destroy]

  # GET all extensions for this account (admin)
  def index
    exts = Current.account.jabvox_user_extensions.includes(:user).order(:extension_jabvox)
    render json: exts.map { |e|
      { id: e.id, user_id: e.user_id, extension: e.extension_jabvox,
        user_name: e.user.name, user_email: e.user.email }
    }
  end

  # GET current user's extension
  def show
    ext = Current.account.jabvox_user_extensions.find_by(user_id: Current.user.id)
    render json: { extension: ext&.extension_jabvox }
  end

  # POST create extension (admin)
  def create
    ext = Current.account.jabvox_user_extensions.new(
      user_id: params[:user_id],
      extension_jabvox: params[:extension]
    )
    if ext.save
      render json: { id: ext.id, user_id: ext.user_id, extension: ext.extension_jabvox,
                     user_name: ext.user.name, user_email: ext.user.email }
    else
      render json: { error: ext.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  # DELETE extension (admin)
  def destroy
    ext = Current.account.jabvox_user_extensions.find(params[:id])
    ext.destroy!
    head :no_content
  end

  private

  def check_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Unauthorized' }, status: :forbidden
  end
end
