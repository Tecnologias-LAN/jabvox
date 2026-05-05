class SuperAdmin::JabvoxIpWhitelistsController < SuperAdmin::ApplicationController
  before_action :fetch_account
  before_action :fetch_entry, only: [:toggle, :destroy]

  def index
    @entries = @account.jabvox_ip_whitelists.ordered
  end

  def create
    @entry = @account.jabvox_ip_whitelists.new(entry_params)
    if @entry.save
      Jabvox::IpWhitelistService.invalidate_cache(@account.id)
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_account_jabvox_ip_whitelists_path(@account), notice: 'IP added successfully'
      # rubocop:enable Rails/I18nLocaleTexts
    else
      @entries = @account.jabvox_ip_whitelists.ordered
      render :index, status: :unprocessable_entity
    end
  end

  def toggle
    @entry.update!(is_active: !@entry.is_active)
    Jabvox::IpWhitelistService.invalidate_cache(@account.id)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_account_jabvox_ip_whitelists_path(@account), notice: 'IP status updated'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def destroy
    @entry.destroy!
    Jabvox::IpWhitelistService.invalidate_cache(@account.id)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_account_jabvox_ip_whitelists_path(@account), notice: 'IP removed'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  def fetch_account
    @account = Account.find(params[:account_id])
  end

  def fetch_entry
    @entry = @account.jabvox_ip_whitelists.find(params[:id])
  end

  def entry_params
    params.require(:jabvox_ip_whitelist).permit(:ip, :is_active, :comment)
  end
end
