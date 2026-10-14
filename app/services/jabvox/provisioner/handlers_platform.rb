# frozen_string_literal: true

# Tercera parte de los handlers de la API Provisioner: las piezas que necesita el Hermes
# APROVISIONADOR para levantar una cuenta completa desde el super admin.
#
# Cubre lo que no tenian handlers.rb / handlers_admin.rb:
#   - hermes_instances.*  Hermes POR CUENTA: crearlo con sus 5 datos (nombre visible, nombre
#                         del agente, URL /p/<agente>/v1, token y allowlist de IPs), leer su
#                         action_token, editarlo, verificarlo y rotar el token.
#   - ai_provider.manual_setup / set_models / list_keys
#                         Equivalentes a la pestana "Por cuenta" del panel de saldo IA: crear
#                         el team sin exigir plan, fijar los modelos permitidos y listar las
#                         virtual keys con su consumo.
#   - automations.*       Reglas de automatizacion de la cuenta (leer, crear, activar).
#
# Mismas reglas que el resto de la API Provisioner:
#   - NUNCA borra nada (no hay operaciones destroy/delete en ningun handler).
#   - Todo se busca SIEMPRE dentro de la cuenta (`account.asociacion`), nunca `Model.find(id)`
#     global, para que una cuenta no pueda alcanzar datos de otra.
#   - Las credenciales no se devuelven salvo donde es el proposito explicito de la operacion
#     (el action_token de Hermes, que el aprovisionador necesita para configurar el agente).
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Provisioner
    module HandlersPlatform # rubocop:disable Metrics/ModuleLength
      module_function

      def h = Jabvox::Provisioner::Handlers

      # ======================================================= Hermes por cuenta
      # Lista los Hermes de una cuenta con su action_token (Hermes -> Jabvox). Es el mismo dato
      # que muestra /super_admin/hermes_instances: el aprovisionador lo necesita para dejar el
      # agente configurado de punta a punta.
      def hermes_list(params)
        account = h.find_account!(params['account_id'])
        { account_id: account.id, connections: account.jabvox_hermes_connections.map { |c| connection_view(c) } }
      end

      def hermes_get(params)
        account = h.find_account!(params['account_id'])
        conn = find_connection!(account, params['connection_id'])
        { account_id: account.id, connection: connection_view(conn) }
      end

      # Crea el Hermes de una cuenta con los mismos 5 campos del formulario "conectar agente IA".
      #
      # La allowlist de IPs es deliberadamente obligatoria: una conexion sin IPs autorizadas no
      # puede ejecutar NADA (ip_allowed? la rechaza), asi que crearla vacia produciria un agente
      # inservible y un fallo silencioso dificil de diagnosticar.
      def hermes_create(params) # rubocop:disable Metrics/AbcSize
        account = h.find_account!(params['account_id'])
        h.error!('name es requerido') if params['name'].blank?
        h.error!('hermes_agent_name es requerido') if params['hermes_agent_name'].blank?
        h.error!('base_url es requerida') if params['base_url'].blank?
        # Se normaliza ANTES de validar: Array('') devuelve [''] (no vacio), asi que mirar el
        # parametro crudo dejaria pasar una allowlist en blanco.
        ips = normalize_ips(params['allowed_ips'])
        h.error!('allowed_ips es requerida (sin IPs el Hermes no puede ejecutar nada)') if ips.empty?

        conn = account.jabvox_hermes_connections.new(
          name_jabvox: params['name'].to_s.strip,
          hermes_agent_name_jabvox: params['hermes_agent_name'].to_s.strip,
          base_url_jabvox: params['base_url'].to_s.strip,
          token_jabvox: params['token'].to_s.presence,
          allowed_ips_jabvox: ips
        )
        h.error!(conn.errors.full_messages.to_sentence) unless conn.save

        { account_id: account.id, connection: connection_view(conn.reload),
          note: 'Guarda el action_token: es la credencial con la que este Hermes ejecuta acciones en Jabvox.' }
      end

      # Edita un Hermes existente. El token en blanco CONSERVA el actual (no lo pisa con vacio),
      # igual que el formulario del dashboard.
      def hermes_update(params) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        account = h.find_account!(params['account_id'])
        conn = find_connection!(account, params['connection_id'])

        attrs = {}
        attrs[:name_jabvox] = params['name'].to_s.strip if params['name'].present?
        attrs[:hermes_agent_name_jabvox] = params['hermes_agent_name'].to_s.strip if params['hermes_agent_name'].present?
        attrs[:base_url_jabvox] = params['base_url'].to_s.strip if params['base_url'].present?
        attrs[:token_jabvox] = params['token'].to_s if params['token'].present?
        if params.key?('allowed_ips')
          ips = normalize_ips(params['allowed_ips'])
          h.error!('allowed_ips no puede quedar vacia (el Hermes no podria ejecutar nada)') if ips.empty?
          attrs[:allowed_ips_jabvox] = ips
        end
        h.error!('nada que actualizar') if attrs.empty?
        h.error!(conn.errors.full_messages.to_sentence) unless conn.update(attrs)

        { account_id: account.id, connection: connection_view(conn.reload) }
      end

      # Rota el action_token: genera uno nuevo e invalida el anterior de inmediato.
      def hermes_rotate_token(params)
        account = h.find_account!(params['account_id'])
        conn = find_connection!(account, params['connection_id'])
        conn.rotate_action_token!
        { account_id: account.id, connection: connection_view(conn.reload),
          note: 'El token anterior quedo invalidado. Actualizalo en el gateway de Hermes.' }
      end

      # Comprueba que el agente responde y guarda el estado en la conexion.
      def hermes_verify(params)
        account = h.find_account!(params['account_id'])
        conn = find_connection!(account, params['connection_id'])
        res = Jabvox::Hermes::SessionsClient.new(
          base_url: conn.base_url_jabvox, token: conn.token_jabvox,
          model: conn.hermes_agent_name_jabvox
        ).health
        conn.mark_status!(success: res.success?, error: res.error)
        { account_id: account.id, connection: connection_view(conn.reload), ok: res.success? }
      rescue StandardError => e
        conn&.mark_status!(success: false, error: e.message)
        h.error!("no se pudo verificar: #{e.message}")
      end

      # ======================================================= Saldo IA por cuenta
      # Crea el team en el proveedor y lo liga a la cuenta SIN exigir plan, con un saldo inicial
      # opcional en USD. Equivale al boton "crear team" de la pestana "Por cuenta" del panel.
      def ai_provider_manual_setup(params)
        account = h.find_account!(params['account_id'])
        cents = usd_to_cents(params['initial_usd'])
        result = Jabvox::AiProvider::BalanceService.new(account).manual_setup!(initial_cents: cents)
        h.error!("no se pudo crear el team: #{result.error}") unless result.success?

        result.provider_account.summary
      end

      # Fija a que modelos puede acceder el team de la cuenta.
      #
      # OJO con la semantica de LiteLLM: `models: []` significa "sin restriccion" (acceso a
      # todos), no "ninguno". Por eso enviar la lista vacia se trata como quitar el limite y se
      # dice explicitamente en la respuesta, para que el aprovisionador no crea que bloqueo algo.
      def ai_provider_set_models(params)
        account = h.find_account!(params['account_id'])
        pa = provider_account!(account)
        models = Array(params['models']).map(&:to_s).reject(&:blank?)

        resp = Jabvox::AiProvider::Client.new.update_team_models(pa.team_id_jabvox, models)
        h.error!("no se pudieron fijar los modelos: #{resp.error}") unless resp.success?
        pa.update!(remote_models_jabvox: models, synced_at_jabvox: Time.current)

        { account_id: account.id, team_id: pa.team_id_jabvox, models: models,
          unrestricted: models.empty?,
          note: models.empty? ? 'Lista vacia = acceso a TODOS los modelos (sin restriccion).' : nil }.compact
      end

      # Lista las virtual keys del team con su consumo, igual que la pestana "Por cuenta".
      # Nunca devuelve la key en claro: el proveedor solo la entrega al crearla.
      def ai_provider_list_keys(params)
        account = h.find_account!(params['account_id'])
        pa = provider_account!(account)

        resp = Jabvox::AiProvider::Client.new.list_keys(pa.team_id_jabvox)
        h.error!("no se pudieron listar las keys: #{resp.error}") unless resp.success?

        { account_id: account.id, team_id: pa.team_id_jabvox,
          keys: Array(resp.data['keys']).map { |k| key_view(k) } }
      end

      # ======================================================= Automatizaciones
      def automations_list(params)
        account = h.find_account!(params['account_id'])
        { account_id: account.id, automations: account.automation_rules.order(:id).map { |r| automation_view(r) } }
      end

      def automations_get(params)
        account = h.find_account!(params['account_id'])
        rule = account.automation_rules.find_by(id: params['id']) || h.error!('automatizacion no encontrada')
        { account_id: account.id, automation: automation_view(rule, full: true) }
      end

      def automations_set_active(params)
        account = h.find_account!(params['account_id'])
        rule = account.automation_rules.find_by(id: params['id']) || h.error!('automatizacion no encontrada')
        rule.update!(active: h.to_bool(params['active']))
        { account_id: account.id, automation: automation_view(rule.reload) }
      end

      # ---------------------------------------------------------------- helpers
      def find_connection!(account, id)
        h.error!('connection_id es requerido') if id.blank?
        account.jabvox_hermes_connections.find_by(id: id) || h.error!('conexion Hermes no encontrada en esta cuenta')
      end

      def provider_account!(account)
        pa = JabvoxAiProviderAccount.find_by(account_id: account.id)
        h.error!('la cuenta no tiene team de saldo IA; ejecuta ai_provider.manual_setup primero') if pa.nil? || pa.team_id_jabvox.blank?
        pa
      end

      # Acepta array JSON o texto separado por comas, igual que el formulario del panel.
      def normalize_ips(raw)
        list = raw.is_a?(Array) ? raw : raw.to_s.split(',')
        cleaned = list.map { |ip| ip.to_s.strip }.reject(&:blank?)
        cleaned.each do |ip|
          IPAddr.new(ip)
        rescue IPAddr::Error
          h.error!("IP invalida en allowed_ips: #{ip}")
        end
        cleaned
      end

      def usd_to_cents(usd)
        cents = (usd.to_f * 100).round
        h.error!('initial_usd no puede ser negativo') if cents.negative?
        cents
      end

      # Vista de una conexion Hermes. Incluye el action_token a proposito: es justo el dato que
      # el aprovisionador necesita leer. El token del AGENTE (token_jabvox, la credencial de
      # Jabvox -> Hermes) nunca se devuelve.
      def connection_view(conn)
        {
          id: conn.id, name: conn.name_jabvox, hermes_agent: conn.hermes_agent_name_jabvox,
          base_url: conn.base_url_jabvox, allowed_ips: Array(conn.allowed_ips_jabvox),
          status: conn.status_jabvox, has_agent_token: conn.token_jabvox.present?,
          action_token: conn.action_token_jabvox, last_error: conn.last_error_jabvox
        }
      end

      def key_view(key)
        {
          token_id: key['token'], alias: key['key_alias'],
          spend_usd: key['spend'], max_budget_usd: key['max_budget'],
          models: Array(key['models']), blocked: key['blocked'] == true,
          created_at: key['created_at']
        }
      end

      def automation_view(rule, full: false)
        base = { id: rule.id, name: rule.name, event_name: rule.event_name, active: rule.active }
        return base unless full

        base.merge(description: rule.description, conditions: rule.conditions, actions: rule.actions)
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
