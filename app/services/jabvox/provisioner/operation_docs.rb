# frozen_string_literal: true

# Manual de uso de la API Provisioner: QUE hace cada operacion y CON QUE parametros.
#
# El catalogo (`OperationRegistry.catalog`) solo dice recurso y accion; eso basta para
# autorizar, pero no para USAR la API. Este archivo es lo que el Hermes Aprovisionador lee
# para saber como llamar cada operacion sin tener que adivinar los nombres de los params.
#
# Formato de cada entrada:
#   summary:  una linea de que hace
#   params:   { 'nombre' => 'descripcion' } — los obligatorios llevan "(requerido)"
#   returns:  que devuelve, en una linea
#   notes:    avisos que evitan un error comun (opcional)
#
# Lo que NO esta aqui no existe: toda operacion registrada deberia tener su doc (hay un spec
# que lo verifica). Ninguna operacion borra nada: la API Provisioner no tiene delete.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Provisioner
    module OperationDocs # rubocop:disable Metrics/ModuleLength
      DOCS = {
        # ------------------------------------------------------------------ Cuentas
        'accounts.list' => {
          summary: 'Lista las cuentas de la instalacion.',
          params: { 'page' => 'pagina (50 por pagina, default 1)' },
          returns: 'accounts: [{ id, name, created_at }]'
        },
        'accounts.get' => {
          summary: 'Ficha completa de una cuenta: plan, limites y modulos.',
          params: { 'id' => 'id de la cuenta (requerido)' },
          returns: 'account: { id, name, plan_id, limits, modules, ... }'
        },
        'accounts.create' => {
          summary: 'Crea una cuenta con su usuario administrador.',
          params: {
            'name' => 'nombre de la cuenta (requerido)',
            'admin_email' => 'email del administrador (requerido)',
            'admin_name' => 'nombre del administrador',
            'locale' => "idioma, default 'es'"
          },
          returns: 'account + user creados',
          notes: 'Si el email ya existe se reutiliza ese usuario como admin de la cuenta nueva.'
        },
        'accounts.update' => {
          summary: 'Cambia nombre, locale o atributos de una cuenta.',
          params: { 'id' => 'id de la cuenta (requerido)', 'name' => 'nombre nuevo', 'locale' => 'idioma nuevo' },
          returns: 'account actualizada'
        },

        # ------------------------------------------------------------------ Usuarios
        'users.list' => {
          summary: 'Lista los usuarios de una cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'page' => 'pagina' },
          returns: 'users: [{ id, name, email, role }]'
        },
        'users.get' => {
          summary: 'Ficha de un usuario.',
          params: { 'id' => 'id del usuario (requerido)' },
          returns: 'user: { id, name, email, accounts }'
        },
        'users.create' => {
          summary: 'Crea un usuario y lo agrega a una cuenta.',
          params: {
            'account_id' => 'id de la cuenta (requerido)',
            'email' => 'email (requerido)',
            'name' => 'nombre',
            'role' => "'agent' o 'administrator' (default agent)"
          },
          returns: 'user creado + su rol en la cuenta'
        },
        'users.update' => {
          summary: 'Cambia nombre o rol de un usuario en una cuenta.',
          params: { 'id' => 'id del usuario (requerido)', 'name' => 'nombre nuevo', 'role' => 'rol nuevo' },
          returns: 'user actualizado'
        },

        # ------------------------------------------------------------------ Modulos
        'account_modules.get' => {
          summary: 'Estado de TODOS los modulos Jabvox de una cuenta (cual esta activo y cual no).',
          params: { 'id' => 'id de la cuenta (requerido)' },
          returns: 'modules: { jabvox_cdr_enabled_jabvox: true, ... } + ' \
                   'catalog: [{ key, column, label, enabled }] con el nombre corto y legible de cada modulo',
          notes: 'Usa catalog[].key (p.ej. "cdr") para account_modules.set: es el nombre corto que ' \
                 'espera esa operacion. `modules` usa el nombre de columna completo.'
        },
        'account_modules.set' => {
          summary: 'Activa o desactiva modulos Jabvox de una cuenta.',
          params: {
            'id' => 'id de la cuenta (requerido)',
            'modules' => '(requerido) objeto { modulo: true|false }, p.ej. { "kanban": true, "cdr": false }'
          },
          returns: 'modules + catalog, con el estado completo despues del cambio',
          notes: 'Acepta el nombre corto ("cdr") o la columna completa ("jabvox_cdr_enabled_jabvox"). ' \
                 'Los nombres desconocidos se IGNORAN en silencio: revisa el catalog de la respuesta ' \
                 'para confirmar que el cambio se aplico.'
        },

        # ------------------------------------------------------------------ Planes
        'plans.list' => { summary: 'Lista los planes.', params: {}, returns: 'plans: [...]' },
        'plans.get' => { summary: 'Ficha de un plan.', params: { 'id' => 'id del plan (requerido)' }, returns: 'plan' },
        'plans.create' => {
          summary: 'Crea un plan.',
          params: {
            'name' => 'nombre (requerido)', 'slug' => 'slug unico (requerido)',
            'price_cents' => 'precio en centavos', 'currency' => "moneda (default 'COP')",
            'duration_days' => 'vigencia en dias (default 30)',
            'modules' => 'array de modulos Jabvox que otorga',
            'features' => 'array de features nativas de Chatwoot',
            'limits' => 'objeto de limites por recurso'
          },
          returns: 'plan creado'
        },
        'plans.update' => { summary: 'Edita un plan.', params: { 'id' => 'id (requerido)' }, returns: 'plan actualizado' },
        'plans.set_status' => {
          summary: 'Activa o archiva un plan.',
          params: { 'id' => 'id (requerido)', 'status' => "'active' o 'archived'" },
          returns: 'plan actualizado'
        },
        'plans.assign' => {
          summary: 'Asigna un plan a una cuenta.',
          params: {
            'account_id' => 'id de la cuenta (requerido)', 'plan_id' => 'id del plan (requerido)',
            'expires_at' => 'fecha de expiracion (ISO 8601)'
          },
          returns: 'account con su plan'
        },

        # ------------------------------------------------------------------ Solo lectura
        'payment_gateways.list' => { summary: 'Lista las pasarelas de pago configuradas.', params: {}, returns: 'gateways (sin credenciales)' },
        'transactions.list' => {
          summary: 'Lista transacciones de aprovisionamiento.',
          params: { 'account_id' => 'filtrar por cuenta', 'page' => 'pagina' },
          returns: 'transactions: [...]'
        },
        'transactions.get' => { summary: 'Detalle de una transaccion.', params: { 'id' => 'id (requerido)' }, returns: 'transaction' },
        'analytics_data_sources.list' => {
          summary: 'Fuentes de datos de Analytics de una cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'data_sources (sin credenciales de conexion)'
        },

        # ------------------------------------------------------------------ Limites
        'limits.get' => {
          summary: 'Limites por recurso de una cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'limits: { inboxes, agents, ai_documents, ... }'
        },
        'limits.set' => {
          summary: 'Fija los limites por recurso de una cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'limits' => '(requerido) objeto { recurso: numero }' },
          returns: 'limits actualizados'
        },

        # ------------------------------------------------------------------ IP whitelist
        'ip_whitelists.list' => {
          summary: 'Lista blanca de IPs de una cuenta (desde donde pueden entrar sus usuarios).',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'ips: [{ id, ip, comment, is_active }]'
        },
        'ip_whitelists.create' => {
          summary: 'Agrega una IP o rango CIDR a la lista blanca de una cuenta.',
          params: {
            'account_id' => 'id de la cuenta (requerido)',
            'ip' => '(requerido) IPv4 suelta, p.ej. 203.0.113.5',
            'comment' => 'nota libre'
          },
          returns: 'la entrada creada',
          notes: 'SOLO IPv4 sueltas: esta lista NO acepta CIDR (10.0.0.0/24 se rechaza). Es distinta ' \
                 'de la allowlist de un Hermes (hermes_instances.*), que si admite rangos CIDR.'
        },
        'ip_whitelists.set_active' => {
          summary: 'Activa o desactiva una entrada de la lista blanca (no la borra).',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'id' => 'id de la entrada (requerido)', 'active' => 'true|false' },
          returns: 'la entrada actualizada'
        },

        # ------------------------------------------------------------------ Softphone
        'softphone.get' => {
          summary: 'Estado del softphone de una cuenta y sus extensiones.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'softphone_enabled + extensions: [{ id, user_id, extension }]'
        },
        'softphone.create_extension' => {
          summary: 'Crea la extension de un usuario.',
          params: {
            'account_id' => 'id de la cuenta (requerido)', 'user_id' => 'id del usuario (requerido)',
            'extension' => 'numero de extension (requerido)'
          },
          returns: 'la extension creada'
        },
        'softphone.set_enabled' => {
          summary: 'Activa o desactiva el softphone de la cuenta, o la extension de un usuario.',
          params: {
            'account_id' => 'id de la cuenta (requerido)', 'enabled' => 'true|false',
            'user_id' => 'si se indica, aplica a la extension WebRTC de ese usuario'
          },
          returns: 'estado actualizado'
        },

        # ------------------------------------------------------------------ Hermes por cuenta
        'hermes_tokens.list' => {
          summary: 'Tokens de accion de los Hermes de una cuenta (alias historico de hermes_instances.list).',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'hermes: [{ id, name, base_url, action_token }]'
        },
        'hermes_instances.list' => {
          summary: 'Lista los Hermes de una cuenta con su action_token.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'connections: [{ id, name, hermes_agent, base_url, allowed_ips, status, action_token }]'
        },
        'hermes_instances.get' => {
          summary: 'Ficha de un Hermes de la cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'connection_id' => 'id de la conexion (requerido)' },
          returns: 'connection'
        },
        'hermes_instances.create' => {
          summary: 'Crea el Hermes de una cuenta (los 5 datos del formulario "conectar agente IA").',
          params: {
            'account_id' => 'id de la cuenta (requerido)',
            'name' => 'nombre visible, p.ej. "Mi agente" (requerido)',
            'hermes_agent_name' => 'nombre del agente en Hermes, p.ej. "mi-agente" (requerido)',
            'base_url' => 'URL del agente: http://tu-hermes:PUERTO/p/<agente>/v1 (requerido)',
            'token' => 'Bearer token del agente (Jabvox -> Hermes)',
            'allowed_ips' => '(requerido) IPs o CIDR autorizados; array o texto separado por comas',
            'agent_id' => 'id del agente del Chat IA al que ligar este Hermes (muy recomendado)'
          },
          returns: 'connection creada con su action_token (Hermes -> Jabvox), el agent ligado y, ' \
                   'si no se ligo ninguno, un warning explicando que aun no aparece en el Chat IA',
          notes: 'La URL debe incluir el prefijo /p/<agente>/v1 y usar el mismo host:puerto que los demas ' \
                 'agentes. allowed_ips es obligatoria: sin IPs el Hermes no puede ejecutar NADA. ' \
                 'El action_token se genera solo: es la credencial con la que ese Hermes actua sobre la cuenta. ' \
                 'Sin `agent_id` el Hermes queda creado pero NO visible en el Chat IA: hay que ligarlo ' \
                 'despues con hermes_agents.set_connections.'
        },
        'hermes_instances.update' => {
          summary: 'Edita los datos del Hermes de una cuenta.',
          params: {
            'account_id' => 'id de la cuenta (requerido)', 'connection_id' => 'id de la conexion (requerido)',
            'name' => 'nombre visible', 'hermes_agent_name' => 'nombre del agente',
            'base_url' => 'URL del agente', 'token' => 'token del agente',
            'allowed_ips' => 'IPs autorizadas (no puede quedar vacia)'
          },
          returns: 'connection actualizada',
          notes: 'El token en blanco CONSERVA el actual: no lo pisa con vacio.'
        },
        'hermes_instances.rotate_token' => {
          summary: 'Genera un action_token nuevo e invalida el anterior.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'connection_id' => 'id de la conexion (requerido)' },
          returns: 'connection con el token nuevo',
          notes: 'El token anterior deja de funcionar de inmediato: hay que actualizarlo en el gateway de Hermes.'
        },
        'hermes_instances.verify' => {
          summary: 'Comprueba que el agente responde y guarda el estado en la conexion.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'connection_id' => 'id de la conexion (requerido)' },
          returns: 'connection + ok: true|false'
        },

        # ------------------------------------------------------------------ Agentes del Chat IA
        'hermes_agents.list' => {
          summary: 'Lista los agentes del Chat IA de una cuenta y que Hermes tiene ligado cada uno.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'agents: [{ id, name, status, user: {id,name,email}, connections, connection_ids }]'
        },
        'hermes_agents.create' => {
          summary: 'Crea un agente del Chat IA ligado a un usuario, y opcionalmente le liga Hermes.',
          params: {
            'account_id' => 'id de la cuenta (requerido)',
            'user_id' => 'id del usuario de la cuenta al que pertenece el agente (requerido)',
            'name' => 'nombre visible del agente (requerido)',
            'description' => 'descripcion libre',
            'connection_ids' => 'array de ids de Hermes a ligarle'
          },
          returns: 'agent creado con sus conexiones',
          notes: 'Los permisos del agente SON los del usuario ligado: se derivan de su rol en la ' \
                 'cuenta automaticamente. El usuario debe pertenecer a la cuenta y solo puede tener ' \
                 'UN agente en ella.'
        },
        'hermes_agents.update' => {
          summary: 'Edita un agente (nombre, descripcion, estado) y/o sus Hermes ligados.',
          params: {
            'account_id' => 'id de la cuenta (requerido)', 'agent_id' => 'id del agente (requerido)',
            'name' => 'nombre nuevo', 'description' => 'descripcion nueva',
            'status' => "'active' o 'disabled'", 'connection_ids' => 'array de ids de Hermes'
          },
          returns: 'agent actualizado'
        },
        'hermes_agents.set_connections' => {
          summary: 'Liga a un agente los Hermes que puede usar (REEMPLAZA la lista actual).',
          params: {
            'account_id' => 'id de la cuenta (requerido)', 'agent_id' => 'id del agente (requerido)',
            'connection_ids' => '(requerido) array de ids de Hermes; [] los desliga todos'
          },
          returns: 'agent con sus conexiones',
          notes: 'Es el paso que deja operativo un Hermes recien creado: sin agente ligado NO aparece ' \
                 'en el Chat IA de la cuenta. Un Hermes solo puede pertenecer a UN agente: ligarlo a ' \
                 'otro falla en vez de robarselo.'
        },

        # ------------------------------------------------------------------ Saldo IA
        'saldo.get' => {
          summary: 'Saldo de IA de una cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'saldo disponible y consumido'
        },
        'ai_provider.list' => {
          summary: 'Cuentas con team de saldo IA y cuales no lo tienen.',
          params: {},
          returns: 'lista de cuentas con su team'
        },
        'ai_provider.get' => {
          summary: 'Team de saldo IA de una cuenta: presupuesto, consumo y modelos.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'team_id, presupuesto, consumo, modelos'
        },
        'ai_provider.setup' => {
          summary: 'Crea el team y le aplica el saldo DEL PLAN de la cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'el team creado',
          notes: 'Falla si la cuenta no tiene plan. Para crearlo sin plan usa ai_provider.manual_setup.'
        },
        'ai_provider.manual_setup' => {
          summary: 'Crea el team y lo liga a la cuenta SIN exigir plan, con saldo inicial opcional.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'initial_usd' => 'saldo inicial en USD (default 0)' },
          returns: 'el team creado',
          notes: 'Equivale al boton "crear team" de la pestana "Por cuenta" del panel de saldo IA. ' \
                 'Es el primer paso para levantar el saldo de una cuenta nueva.'
        },
        'ai_provider.set_models' => {
          summary: 'Fija a que modelos puede acceder el team de la cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'models' => 'array de nombres de modelo' },
          returns: 'los modelos aplicados',
          notes: 'OJO: models vacio significa acceso a TODOS los modelos (sin restriccion), no "ninguno".'
        },
        'ai_provider.create_key' => {
          summary: 'Crea una virtual key del team de la cuenta y la devuelve UNA sola vez.',
          params: {
            'account_id' => 'id de la cuenta (requerido)',
            'key_alias' => "alias de la key (default 'crm-<id>-key')",
            'models' => 'array de modelos a los que da acceso',
            'max_budget_usd' => 'tope de gasto de la key en USD'
          },
          returns: 'key (en claro, solo esta vez) + token_id',
          notes: 'GUARDA la key al recibirla: no se puede volver a leer, solo rotar. El tope de la key ' \
                 'no puede superar el del team. Esta es la key con la que el Hermes de la cuenta consume IA.'
        },
        'ai_provider.list_keys' => {
          summary: 'Lista las virtual keys del team con su consumo.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'keys: [{ token_id, alias, spend_usd, max_budget_usd, models, blocked }]',
          notes: 'Nunca devuelve la key en claro: el proveedor solo la entrega al crearla.'
        },
        'ai_provider.recharge' => {
          summary: 'Suma saldo comprado al team de una cuenta (se acumula).',
          params: {
            'account_id' => 'id de la cuenta (requerido)',
            'amount_cents' => 'monto en centavos de USD (requerido)',
            'reference' => '(requerido) referencia unica para idempotencia'
          },
          returns: 'el team con el saldo actualizado',
          notes: 'Idempotente por reference: repetir la misma referencia NO recarga dos veces.'
        },

        # ------------------------------------------------------------------ Automatizaciones
        'automations.list' => {
          summary: 'Lista las reglas de automatizacion de una cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'automations: [{ id, name, event_name, active }]'
        },
        'automations.get' => {
          summary: 'Detalle de una regla, con sus condiciones y acciones.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'id' => 'id de la regla (requerido)' },
          returns: 'automation: { id, name, event_name, active, conditions, actions }'
        },
        'automations.set_active' => {
          summary: 'Activa o desactiva una regla de automatizacion.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'id' => 'id de la regla (requerido)', 'active' => 'true|false' },
          returns: 'la regla actualizada'
        },

        # ------------------------------------------------------------------ Contactos
        'leads.list' => {
          summary: 'Lista los contactos de una cuenta.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'page' => 'pagina (50 por pagina)' },
          returns: 'leads: [{ id, name, phone, email }]'
        },
        'leads.import_sources' => {
          summary: 'Fuentes de importacion de contactos configuradas.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'sources: [...]'
        },
        'leads.trigger_import' => {
          summary: 'Dispara una importacion de contactos.',
          params: { 'account_id' => 'id de la cuenta (requerido)', 'source_id' => 'id de la fuente (requerido)' },
          returns: 'estado de la importacion'
        },
        'leads.export_targets' => {
          summary: 'Destinos de exportacion de contactos configurados.',
          params: { 'account_id' => 'id de la cuenta (requerido)' },
          returns: 'targets: [...]'
        }
      }.freeze

      module_function

      def for(operation)
        DOCS[operation.to_s]
      end

      # Catalogo + manual, fusionados: lo que el Hermes necesita para usar la API sin adivinar.
      # `only` limita a las operaciones que el token tiene permitidas.
      def catalog_with_docs(only: nil)
        ops = Jabvox::Provisioner::OperationRegistry.catalog
        ops = ops.slice(*Array(only)) if only
        ops.to_h do |op, meta|
          [op, meta.merge(DOCS[op] || { summary: 'Sin documentacion.', params: {}, returns: nil })]
        end
      end

      # Operaciones registradas que se quedaron sin doc (lo vigila un spec).
      def undocumented
        Jabvox::Provisioner::OperationRegistry.catalog.keys - DOCS.keys
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
