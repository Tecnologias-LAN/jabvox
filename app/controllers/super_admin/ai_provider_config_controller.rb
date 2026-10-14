# frozen_string_literal: true

# Pantalla del Super Admin para configurar el proveedor de API de IA: nombre, URL base,
# master key (cifrada, nunca precargada ni mostrada) y habilitado. Permite probar la conexión.
# rubocop:disable Rails/I18nLocaleTexts
class SuperAdmin::AiProviderConfigController < SuperAdmin::ApplicationController # rubocop:disable Metrics/ClassLength
  # Validación del catálogo de modelos, aparte para no engordar el controller.
  module ModelValidation
    # Rechaza modelos que el proveedor no expone. Si el proxy no reporta catálogo, no se
    # bloquea nada (no inventar una restricción sobre información que no tenemos).
    def unknown_models_error(models)
      return nil if models.empty?

      catalog = client.model_names
      return nil if catalog.empty?

      unknown = models - catalog
      unknown.empty? ? nil : "El proveedor no expone estos modelos: #{unknown.join(', ')}."
    end
  end
  include ModelValidation

  TABS = %w[connection accounts balances].freeze
  # Tope de cuentas que se ofrecen en el selector. Evita renderizar un <select> gigantesco.
  ACCOUNT_OPTIONS_LIMIT = 500

  def show # rubocop:disable Metrics/AbcSize
    @config = JabvoxAiProviderConfig.instance
    @summary = @config.safe_summary
    @tab = TABS.include?(params[:tab]) ? params[:tab] : 'connection'
    # Datos de las pestañas "Por cuenta" y "Saldos" (se cargan siempre; son ligeros).
    return unless %w[accounts balances].include?(@tab)

    @rows = load_account_rows
    @account_options = account_options
    @orphans = JabvoxAiProviderAccount.orphans.order(:team_alias_jabvox, :id).limit(200)
    load_model_catalog
    # Virtual keys de UNA cuenta con su consumo (?show_keys=<account_id>). Se cargan bajo
    # demanda y no al pintar la tabla: cada consulta es una llamada al proveedor, y hacerla
    # para las 200 filas dejaria la pantalla colgada.
    load_account_keys if params[:show_keys].present?

    # Diagnóstico de un team concreto (?inspect_team=<id>): qué ve Jabvox realmente en el
    # proveedor. Sirve para entender por qué una key creada fuera no aparece en la cuenta.
    return if params[:inspect_team].blank?

    @inspection = Jabvox::AiProvider::TeamInspector.new(config: @config, client: client)
                                                   .call(params[:inspect_team])
  end

  # Fija los modelos a los que puede acceder el team de una cuenta. Vacío = todos.
  def set_team_models
    provider_account = JabvoxAiProviderAccount.find(params[:provider_account_id])
    return redirect_tab('accounts', 'Ese team aún no existe en el proveedor.', :alert) if provider_account.team_id_jabvox.blank?

    models = Array(params[:models]).map(&:to_s).reject(&:blank?)
    # Aunque el Super Admin puede todo, un nombre de modelo inexistente dejaría al team sin
    # acceso a ninguno (LiteLLM lo interpreta como restricción a un modelo que no existe).
    error = unknown_models_error(models) || apply_team_models(provider_account, models)
    return redirect_tab('accounts', error, :alert) if error

    redirect_tab('accounts', models_saved_message(provider_account, models))
  rescue ActiveRecord::RecordNotFound
    redirect_tab('accounts', 'No existe ese team.', :alert)
  rescue StandardError => e
    Rails.logger.error("[AiProviderConfig] modelos: #{e.class}: #{e.message}")
    redirect_tab('accounts', 'No se pudieron asignar los modelos.', :alert)
  end

  # Trae TODO de LiteLLM y lo refleja en Jabvox: importa los teams que no existían aquí,
  # actualiza los que sí, y deja como "huérfanos" los que no se pueden mapear a una cuenta.
  def sync_provider
    config = JabvoxAiProviderConfig.instance
    return redirect_tab('accounts', 'Configura URL, master key y habilita el proveedor antes de sincronizar.', :alert) unless config.configured?

    result = Jabvox::AiProvider::SyncService.new.sync_all!
    if result.success?
      redirect_tab('accounts', "Sincronización completa: #{result.imported} importados, " \
                               "#{result.updated} actualizados, #{result.linked} ligados " \
                               "automáticamente. Huérfanos pendientes: #{result.orphans}.")
    else
      redirect_tab('accounts', "No se pudo sincronizar: #{result.error}", :alert)
    end
  rescue StandardError => e
    Rails.logger.error("[AiProviderConfig] sincronizar: #{e.class}: #{e.message}")
    redirect_tab('accounts', 'No se pudo sincronizar con el proveedor.', :alert)
  end

  # Liga un team ya existente en el proveedor (huérfano) a una cuenta de Jabvox.
  def link_account
    provider_account = JabvoxAiProviderAccount.find(params[:provider_account_id])
    account = Account.find_by(id: params[:account_id])
    return redirect_tab('accounts', "No existe la cuenta #{params[:account_id]}.", :alert) if account.nil?

    Jabvox::AiProvider::SyncService.new.link_to_account!(provider_account, account)
    redirect_tab('accounts', "Team #{provider_account.team_id_jabvox} ligado a la cuenta #{account.id}.")
  rescue ArgumentError => e
    redirect_tab('accounts', e.message, :alert)
  rescue ActiveRecord::RecordNotFound
    redirect_tab('accounts', 'No existe ese team.', :alert)
  rescue StandardError => e
    Rails.logger.error("[AiProviderConfig] ligar: #{e.class}: #{e.message}")
    redirect_tab('accounts', 'No se pudo ligar el team a la cuenta.', :alert)
  end

  # Desliga la cuenta de su team. El team NO se borra en el proveedor: queda huérfano.
  def unlink_account
    provider_account = JabvoxAiProviderAccount.find(params[:provider_account_id])
    Jabvox::AiProvider::SyncService.new.unlink!(provider_account)
    redirect_tab('accounts', "Team #{provider_account.team_id_jabvox} desligado. Sigue existiendo en el proveedor.")
  rescue ActiveRecord::RecordNotFound
    redirect_tab('accounts', 'No existe ese team.', :alert)
  rescue StandardError => e
    Rails.logger.error("[AiProviderConfig] desligar: #{e.class}: #{e.message}")
    redirect_tab('accounts', 'No se pudo desligar el team.', :alert)
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

  # Pestaña "Por cuenta": crea un team y lo liga a CUALQUIER cuenta manualmente (sin depender
  # del plan), con un saldo inicial opcional en USD que va al saldo comprado.
  def manual_setup
    account = Account.find_by(id: params[:account_id])
    return redirect_tab('accounts', "No existe la cuenta #{params[:account_id]}.", :alert) if account.nil?

    initial_cents = (params[:initial_usd].to_f * 100).round
    result = Jabvox::AiProvider::BalanceService.new(account).manual_setup!(initial_cents: initial_cents)
    if result.success?
      redirect_tab('accounts', "Team creado para la cuenta #{account.id}: #{result.provider_account.team_id_jabvox}.")
    else
      redirect_tab('accounts', "No se pudo crear el team: #{result.error}", :alert)
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

  # Filas de la tabla: cuentas con plan de IA + CUALQUIER cuenta que ya tenga un team ligado
  # (aunque su plan no otorgue saldo, p. ej. las importadas de LiteLLM o dadas de alta a mano).
  def load_account_rows
    plan_ids = JabvoxPlan.where('ai_budget_cents_jabvox > 0').pluck(:id)
    linked_ids = JabvoxAiProviderAccount.linked.pluck(:account_id)
    accounts = Account.where(jabvox_plan_id: plan_ids).or(Account.where(id: linked_ids))
                      .order(:id).limit(200)
    provider_accounts = JabvoxAiProviderAccount.where(account_id: accounts.map(&:id)).index_by(&:account_id)
    accounts.map do |acc|
      pa = provider_accounts[acc.id]
      { account: acc, plan: acc.jabvox_plan, provider_account: pa, connected: pa&.team_id_jabvox.present? }
    end
  end

  # Virtual keys del team de una cuenta, con su consumo. El proveedor NUNCA devuelve la key
  # en claro (solo al crearla): aqui se ve su alias, su hash, el gasto y el tope.
  def load_account_keys
    @keys_account_id = params[:show_keys].to_i
    pa = JabvoxAiProviderAccount.find_by(account_id: @keys_account_id)
    if pa.nil? || pa.team_id_jabvox.blank?
      @keys_error = 'Esa cuenta aun no tiene team en el proveedor.'
      return
    end

    resp = client.list_keys(pa.team_id_jabvox)
    if resp.success?
      @account_keys = Array(resp.data['keys'])
    else
      @keys_error = resp.error
    end
  end

  # UN cliente por request, con presupuesto de tiempo: esta pantalla encadena varias
  # llamadas (catálogo de modelos + diagnóstico) y un proveedor lento no debe colgarla.
  # Catálogo con proveedor por modelo: permite elegir modelos sueltos ('gpt-4') agrupados
  # por proveedor, en vez de tratar cada proveedor como un bloque indivisible.
  def load_model_catalog
    @model_catalog = @config.configured? ? client.model_catalog : []
    @available_models = @model_catalog.pluck(:name)
    # { 'openai' => ['gpt-4', ...], 'anthropic' => [...] }
    @models_by_provider = @model_catalog.group_by { |m| m[:provider] }
                                        .transform_values { |ms| ms.pluck(:name) }
  end

  def client
    @client ||= Jabvox::AiProvider::Client.new(config: JabvoxAiProviderConfig.instance)
  end

  # Escribe los modelos en el proveedor y refleja el resultado localmente.
  # Devuelve el mensaje de error, o nil si fue bien.
  def apply_team_models(provider_account, models)
    resp = client.update_team_models(provider_account.team_id_jabvox, models)
    return "No se pudieron asignar los modelos: #{resp.error}" unless resp.success?

    provider_account.update(remote_models_jabvox: models, synced_at_jabvox: Time.current)
    nil
  end

  def models_saved_message(provider_account, models)
    label = models.empty? ? 'todos los modelos' : models.join(', ')
    "Team #{provider_account.team_id_jabvox}: acceso a #{label}."
  end

  # Opciones del selector de cuentas: [etiqueta, id]. Sustituye al campo numérico a ciegas.
  def account_options
    Account.order(:id).limit(ACCOUNT_OPTIONS_LIMIT).pluck(:id, :name).map do |id, name|
      ["##{id} — #{name}", id]
    end
  end
end
# rubocop:enable Rails/I18nLocaleTexts
