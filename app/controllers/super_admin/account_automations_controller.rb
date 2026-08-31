# Panel por cuenta del módulo de Automatizaciones Avanzadas (flujos nativos).
# Solo dos operaciones: activar/desactivar el módulo y fijar el tope de flujos.
class SuperAdmin::AccountAutomationsController < SuperAdmin::ApplicationController
  before_action :fetch_account
  before_action :fetch_config

  # rubocop:disable Rails/I18nLocaleTexts
  def index
    @flows_count = @account.jabvox_flows.count
    @plan_limit = @account.effective_limit_for(:advanced_flows).to_i
  end

  # El módulo y la columna del feature flag se mueven juntos: si quedaran
  # desincronizados la cuenta vería el menú sin poder usar la API (o al revés).
  def toggle
    enabling = !@config.enabled?
    @config.update!(enabled: enabling, max_flows: max_flows_param)
    @account.update!(jabvox_advanced_automations_enabled_jabvox: enabling)

    redirect_to super_admin_account_account_automations_path(@account),
                notice: enabling ? 'Módulo de flujos activado para esta cuenta.' : 'Módulo de flujos desactivado para esta cuenta.'
  end

  def update_limit
    if @config.update(max_flows: max_flows_param)
      redirect_to super_admin_account_account_automations_path(@account), notice: 'Límite de flujos actualizado.'
    else
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: "No se pudo guardar el límite: #{@config.errors.full_messages.to_sentence}"
    end
  end
  # rubocop:enable Rails/I18nLocaleTexts

  private

  def fetch_account
    @account = Account.find(params[:account_id])
  end

  def fetch_config
    @config = @account.account_automation_config || @account.build_account_automation_config
    @config.save! if @config.new_record?
  end

  # Vacío/blank => nil (ilimitado, salvo lo que dicte el plan).
  def max_flows_param
    raw = params[:max_flows]
    raw.blank? ? nil : raw.to_i
  end
end
