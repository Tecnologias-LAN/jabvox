# frozen_string_literal: true

# Pantalla del Super Admin para configurar el proveedor de API de IA: nombre, URL base,
# master key (cifrada, nunca precargada ni mostrada) y habilitado. Permite probar la conexión.
# rubocop:disable Rails/I18nLocaleTexts
class SuperAdmin::AiProviderConfigController < SuperAdmin::ApplicationController
  TABS = %w[connection accounts balances].freeze

  def show
    @config = JabvoxAiProviderConfig.instance
    @summary = @config.safe_summary
    @tab = TABS.include?(params[:tab]) ? params[:tab] : 'connection'
    # Datos de las pestañas "Por cuenta" y "Saldos" (se cargan siempre; son ligeros).
    @rows = load_account_rows if %w[accounts balances].include?(@tab)
  end

  # Guarda la config. La master key en blanco = conservar la actual (nunca se sobreescribe con
  # vacío, y nunca se precarga en el HTML).
  def update # rubocop:disable Metrics/AbcSize
    config = JabvoxAiProviderConfig.instance
    attrs = {
      provider_name_jabvox: params[:provider_name].presence || config.provider_name_jabvox,
      base_url_jabvox: params[:base_url].to_s.strip.presence,
      enabled_jabvox: ActiveModel::Type::Boolean.new.cast(params[:enabled])
    }
    key = params[:master_key].to_s.strip
    attrs[:master_key_jabvox] = key if key.present?
    config.update!(attrs)
    redirect_tab('connection', 'Configuración del proveedor guardada.')
  rescue ActiveRecord::RecordInvalid => e
    redirect_tab('connection', "No se pudo guardar: #{e.record.errors.full_messages.join('; ')}", :alert)
  rescue StandardError => e
    Rails.logger.error("[AiProviderConfig] guardar: #{e.class}: #{e.message}")
    redirect_tab('connection', 'No se pudo guardar la configuración.', :alert)
  end

  # Prueba la conexión contra el proveedor (consulta /model/info). Actualiza el estado.
  def test_connection
    config = JabvoxAiProviderConfig.instance
    return redirect_to super_admin_ai_provider_config_path, alert: 'Configura URL, master key y habilítalo antes de probar.' unless config.configured?

    resp = Jabvox::AiProvider::Client.new(config: config).models_info
    if resp.success?
      config.mark_connected!
      redirect_tab('connection', 'Conexión exitosa con el proveedor.')
    else
      config.mark_error!(resp.error)
      redirect_tab('connection', "El proveedor respondió con error: #{resp.error}", :alert)
    end
  rescue StandardError => e
    JabvoxAiProviderConfig.instance.mark_error!(e.message)
    redirect_tab('connection', 'No se pudo conectar con el proveedor.', :alert)
  end

  # Pestaña "Por cuenta": crea el team en el proveedor y lo asigna a la cuenta (aplica el
  # saldo del plan). Toda la lógica pasa por BalanceService (nunca llama al proxy directo).
  def provision
    account = Account.find(params[:account_id])
    plan = account.jabvox_plan
    return redirect_tab('accounts', 'La cuenta no tiene plan asignado.', :alert) if plan.nil?

    result = Jabvox::AiProvider::BalanceService.new(account).apply_plan!(plan, reference: "superadmin:#{account.id}")
    if result.success?
      redirect_tab('accounts', "Cuenta #{account.id} aprovisionada. Team: #{result.provider_account.team_id_jabvox}.")
    else
      redirect_tab('accounts', "No se pudo aprovisionar: #{result.error}", :alert)
    end
  end

  # Pestaña "Por cuenta": recarga saldo COMPRADO (se acumula). El monto llega en USD.
  def recharge
    account = Account.find(params[:account_id])
    cents = (params[:amount_usd].to_f * 100).round
    return redirect_tab('accounts', 'El monto debe ser positivo.', :alert) if cents <= 0

    reference = params[:reference].presence || "superadmin:#{account.id}:#{Time.current.to_i}"
    result = Jabvox::AiProvider::BalanceService.new(account).purchase!(amount_cents: cents, reference: reference)
    if result.success?
      redirect_tab('accounts', "Recargados $#{format('%.2f', cents / 100.0)} USD a la cuenta #{account.id}.")
    else
      redirect_tab('accounts', "No se pudo recargar: #{result.error}", :alert)
    end
  end

  private

  def redirect_tab(tab, msg, kind = :notice)
    redirect_to super_admin_ai_provider_config_path(tab: tab), kind => msg
  end

  # Cuentas con plan que otorga saldo de IA + su desglose (para las pestañas por cuenta/saldos).
  def load_account_rows
    plan_ids = JabvoxPlan.where('ai_budget_cents_jabvox > 0').pluck(:id)
    accounts = Account.where(jabvox_plan_id: plan_ids).order(:id).limit(200)
    provider_accounts = JabvoxAiProviderAccount.where(account_id: accounts.map(&:id)).index_by(&:account_id)
    accounts.map do |acc|
      pa = provider_accounts[acc.id]
      { account: acc, plan: acc.jabvox_plan, provider_account: pa, connected: pa&.team_id_jabvox.present? }
    end
  end
end
# rubocop:enable Rails/I18nLocaleTexts
