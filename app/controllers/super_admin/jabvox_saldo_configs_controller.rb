class SuperAdmin::JabvoxSaldoConfigsController < SuperAdmin::ApplicationController
  before_action :fetch_account, only: [:show, :update]

  def index
    @configs = JabvoxSaldoConfig.includes(:account).order(created_at: :desc)
    @statuses = @configs.each_with_object({}) do |config, hash|
      hash[config.id] = Jabvox::SaldoService.new(config).fetch_balance
    rescue StandardError => e
      hash[config.id] = { connected: false, balance: config.cached_balance_jabvox, currency: 'COP', message: e.message }
    end
  end

  def new
    @config = JabvoxSaldoConfig.new
    @accounts = Account.order(:name)
  end

  def create
    account = Account.find(create_params[:account_id])
    @config = account.jabvox_saldo_config || account.build_jabvox_saldo_config

    attrs = create_params.except('account_id').to_h
    attrs.delete('api_secret_jabvox') if attrs['api_secret_jabvox'].blank?
    @config.assign_attributes(attrs)

    if @config.save
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_jabvox_saldo_configs_path, notice: 'Saldo config saved successfully'
      # rubocop:enable Rails/I18nLocaleTexts
    else
      @accounts = Account.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    config = JabvoxSaldoConfig.find(params[:id])
    config.destroy!
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_jabvox_saldo_configs_path, notice: 'Saldo config deleted'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def show
    @config = @account.jabvox_saldo_config || @account.build_jabvox_saldo_config
    @status = safe_fetch_status(@account.jabvox_saldo_config)
  end

  def update
    @config = @account.jabvox_saldo_config || @account.build_jabvox_saldo_config

    attrs = config_params.to_h
    attrs.delete('api_secret_jabvox') if attrs['api_secret_jabvox'].blank?

    @config.update!(attrs)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_account_jabvox_saldo_config_path(@account), notice: 'Saldo config updated successfully'
    # rubocop:enable Rails/I18nLocaleTexts
  rescue ActiveRecord::RecordInvalid
    @status = safe_fetch_status(@account.jabvox_saldo_config)
    render :show, status: :unprocessable_entity
  end

  private

  def fetch_account
    @account = Account.find(params[:account_id])
  end

  def safe_fetch_status(config)
    Jabvox::SaldoService.new(config).fetch_balance
  rescue StandardError => e
    { connected: false, balance: config&.cached_balance_jabvox, currency: 'COP', message: e.message }
  end

  def create_params
    params.require(:jabvox_saldo_config).permit(
      :account_id,
      :name_jabvox,
      :proxy_url_jabvox,
      :api_key_jabvox,
      :api_secret_jabvox,
      :is_active_jabvox
    )
  end

  def config_params
    params.require(:jabvox_saldo_config).permit(
      :name_jabvox,
      :proxy_url_jabvox,
      :api_key_jabvox,
      :api_secret_jabvox,
      :is_active_jabvox
    )
  end
end
