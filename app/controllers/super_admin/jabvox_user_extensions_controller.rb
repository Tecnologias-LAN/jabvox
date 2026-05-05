class SuperAdmin::JabvoxUserExtensionsController < SuperAdmin::ApplicationController
  before_action :fetch_account
  before_action :fetch_entry, only: [:destroy]

  def index
    @extensions = @account.jabvox_user_extensions.includes(:user).order(:extension_jabvox)
    @account_users = @account.users.order(:name)
    @used_user_ids = @extensions.pluck(:user_id)
  end

  def create
    @entry = @account.jabvox_user_extensions.new(entry_params)
    if @entry.save
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_account_jabvox_user_extensions_path(@account), notice: 'Extension added'
      # rubocop:enable Rails/I18nLocaleTexts
    else
      @extensions = @account.jabvox_user_extensions.includes(:user).order(:extension_jabvox)
      @account_users = @account.users.order(:name)
      @used_user_ids = @extensions.pluck(:user_id)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy!
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_account_jabvox_user_extensions_path(@account), notice: 'Extension removed'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  def fetch_account
    @account = Account.find(params[:account_id])
  end

  def fetch_entry
    @entry = @account.jabvox_user_extensions.find(params[:id])
  end

  def entry_params
    params.require(:jabvox_user_extension).permit(:user_id, :extension_jabvox)
  end
end
