# frozen_string_literal: true

# Cliente del proveedor de API de IA (proxy tipo LiteLLM, GENÉRICO). Todas las llamadas
# administrativas usan la master key (leída CIFRADA de BD, nunca hardcodeada ni enviada al
# frontend). Distingue el 429 de "saldo agotado" del de "rate limit", reintenta solo errores
# transitorios (5xx y rate limit) con backoff, y devuelve un Result tipado.
#
# En dev/test, si el proveedor no está configurado, usa un adaptador MOCK en memoria para
# poder verificar el flujo completo sin llamar al proxy real.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module AiProvider
    class Client
      OPEN_TIMEOUT = 5
      TIMEOUT = 30
      MAX_ATTEMPTS = 4
      # Presupuesto total para TODAS las llamadas de una misma instancia. Un endpoint que
      # encadena varias (listar páginas de keys + modelos + info del team) podía tardar, en
      # el peor caso de reintentos, decenas de minutos: bastaba un proveedor lento para
      # colgar el request y dejar un worker de Puma ocupado todo ese tiempo.
      # Al agotarse, las llamadas siguientes fallan de inmediato en vez de reintentar.
      DEFAULT_BUDGET = 20

      ConfigurationError = Class.new(StandardError)
      # El cliente se quedó sin saldo: requiere recarga, NO reintento.
      BudgetExceededError = Class.new(StandardError)

      # Adapter forzado (solo tests): si se fija, todas las instancias lo usan.
      class << self
        attr_accessor :adapter_override
      end

      Result = Struct.new(:success, :data, :error, :status, keyword_init: true) do
        def success? = success
      end

      # `budget_seconds:` acota el tiempo total que esta instancia puede gastar hablando con
      # el proveedor. nil = sin límite (para jobs en segundo plano, donde tardar no bloquea
      # a nadie). En un request web se deja el valor por defecto.
      def initialize(config: nil, adapter: nil, budget_seconds: DEFAULT_BUDGET)
        @config = config || JabvoxAiProviderConfig.instance
        @adapter = adapter || default_adapter
        @budget_seconds = budget_seconds
        @deadline = budget_seconds ? monotonic_now + budget_seconds : nil
      end

      # ¿Se agotó el presupuesto de tiempo de esta instancia?
      def budget_exhausted?
        @deadline.present? && monotonic_now >= @deadline
      end

      # --- Teams (saldo del cliente) ---
      # `team_id:` permite fijar el id desde Jabvox para que reintentar la creación no genere
      # teams duplicados en el proxy (LiteLLM lo genera solo si no se envía).
      def create_team(alias_name:, max_budget_usd:, models: [], metadata: {}, team_id: nil)
        body = { team_alias: alias_name, models: models,
                 max_budget: max_budget_usd, metadata: metadata }
        body[:team_id] = team_id if team_id.present?
        post('/team/new', **body)
      end

      def team_info(team_id)
        get('/team/info', team_id: team_id)
      end

      # Lista TODOS los teams del proxy. Verificado contra el código de LiteLLM
      # (management_endpoints/team_endpoints.py): `/team/list` devuelve un ARRAY PLANO de
      # teams, no un objeto envuelto. El normalizador de abajo tolera ambas formas por si
      # una versión del proxy lo envuelve.
      def list_teams
        get('/team/list')
      end

      # Borra teams en el proxy. LiteLLM espera la clave `team_ids` (lista), no `team_id`.
      def delete_teams(team_ids)
        post('/team/delete', team_ids: Array(team_ids))
      end

      # SUMA/actualiza el tope ABSOLUTO. El llamador es responsable de leer→sumar→escribir.
      def update_team_budget(team_id, max_budget_usd)
        post('/team/update', team_id: team_id, max_budget: max_budget_usd)
      end

      def block_team(team_id)   = post('/team/block', team_id: team_id)
      def unblock_team(team_id) = post('/team/unblock', team_id: team_id)

      def team_activity(team_id, start_date:, end_date:)
        get('/team/daily/activity', team_id: team_id, start_date: start_date, end_date: end_date)
      end

      # --- Virtual keys ---
      # rubocop:disable Metrics/ParameterLists
      def generate_key(team_id:, key_alias:, models: [], max_budget_usd: nil,
                       allowed_routes: nil, metadata: {})
        body = { team_id: team_id, key_alias: key_alias, models: models, metadata: metadata }
        body[:max_budget] = max_budget_usd unless max_budget_usd.nil?
        body[:allowed_routes] = allowed_routes if allowed_routes
        post('/key/generate', **body)
      end
      # rubocop:enable Metrics/ParameterLists

      def key_info(key)  = get('/key/info', key: key)

      # Lista las keys del team. Verificado contra el código de LiteLLM
      # (management_endpoints/key_management_endpoints.py):
      #   - pagina con `size` (default 10, máximo 100) — sin esto solo se verían 10 keys;
      #   - sin `return_full_object=true` devuelve solo el token como string, no el objeto
      #     con spend/max_budget/blocked, que es justo lo que necesita la UI.
      # Responde { keys: [...], total_count, current_page, total_pages }.
      def list_keys(team_id, page: 1, size: 100)
        get('/key/list', team_id: team_id, page: page, size: size, return_full_object: true)
      end

      # `key` admite tanto la key en claro (sk-...) como su HASH (el `token` que devuelve
      # /key/list). Jabvox siempre usa el hash: así nunca necesita almacenar la key en claro.
      def block_key(key) = post('/key/block', key: key)
      def unblock_key(key) = post('/key/unblock', key: key)

      # Actualiza una key existente (merge patch: lo que no se envía conserva su valor).
      # `models: []` sí se envía: significa "sin restricción", distinto de no tocarlo (nil).
      def update_key(key, max_budget_usd: nil, models: nil)
        body = { key: key }
        body[:max_budget] = max_budget_usd unless max_budget_usd.nil?
        body[:models] = Array(models).map(&:to_s) unless models.nil?
        post('/key/update', **body)
      end

      def models_info = get('/model/info')

      # Nombres de los modelos que expone el proxy, ordenados y sin duplicados.
      # /model/info responde { "data": [ { "model_name": "...", ... } ] } (verificado en
      # proxy_server.py: _model_info_json_response envuelve siempre en "data").
      def model_names
        model_catalog.pluck(:name)
      end

      # Catálogo con el PROVEEDOR de cada modelo, para poder elegir modelos sueltos
      # ('gpt-4') y no solo proveedores enteros ('openai'):
      #   [{ name: 'gpt-4', provider: 'openai' }, ...]
      #
      # El proveedor se toma de `model_info.litellm_provider` (campo requerido en el tipo
      # de LiteLLM) y, si faltara, del prefijo de `litellm_params.model` ("openai/gpt-4").
      def model_catalog
        resp = models_info
        return [] unless resp.success?

        rows = resp.data.is_a?(Hash) ? resp.data['data'] : resp.data
        Array(rows).filter_map { |row| catalog_entry(row) }
                   .uniq { |m| m[:name] }
                   .sort_by { |m| [m[:provider], m[:name]] }
      end

      # Fija los modelos a los que puede acceder el team. [] = sin restricción (todos).
      def update_team_models(team_id, models)
        post('/team/update', team_id: team_id, models: Array(models).map(&:to_s))
      end

      # --- Normalización de la respuesta de /team/list ---
      # Devuelve siempre un Array de Hash, sin importar si el proxy respondió un array plano
      # (comportamiento actual de LiteLLM) o un objeto {"teams"|"data"|"results" => [...]}.
      def self.normalize_team_list(data)
        rows = case data
               when Array then data
               when Hash  then data['teams'] || data['data'] || data['results'] || []
               else []
               end
        Array(rows).select { |r| r.is_a?(Hash) }
      end

      private

      # Una entrada del catálogo, o nil si la fila no trae nombre de modelo.
      def catalog_entry(row)
        return nil unless row.is_a?(Hash)

        name = row['model_name'].to_s.presence
        return nil if name.nil?

        { name: name, provider: extract_provider(row, name) }
      end

      # Proveedor del modelo, por orden de fiabilidad:
      #   1. model_info.litellm_provider (lo que declara el propio LiteLLM)
      #   2. prefijo de litellm_params.model ("openai/gpt-4" → "openai")
      #   3. prefijo del propio model_name, si viene con forma "proveedor/modelo"
      # Si nada de eso existe, se agrupa bajo "otros" en vez de perder el modelo.
      def extract_provider(row, name)
        info = row['model_info']
        declared = info.is_a?(Hash) ? info['litellm_provider'].to_s.presence : nil
        return declared if declared

        params = row['litellm_params']
        raw = params.is_a?(Hash) ? params['model'].to_s : ''
        from_params = raw.include?('/') ? raw.split('/').first.presence : nil
        return from_params if from_params

        name.include?('/') ? name.split('/').first : 'otros'
      end

      def default_adapter
        # Override inyectable (tests): permite forzar el Mock aunque el proveedor esté
        # configurado, sin tocar la lógica de producción.
        return self.class.adapter_override if self.class.adapter_override

        if @config.configured?
          HttpAdapter.new(@config)
        else
          # Sin proveedor configurado (dev/test): mock en memoria, para verificar el flujo.
          Jabvox::AiProvider::MockAdapter.instance
        end
      end

      def get(path, **params)  = with_retries { @adapter.request(:get, path, params: params) }
      def post(path, **body)   = with_retries { @adapter.request(:post, path, body: body) }

      # Reintenta solo errores transitorios (5xx, rate limit). El saldo agotado (BudgetExceeded)
      # se propaga de inmediato sin reintentar.
      def with_retries
        return timed_out_result if budget_exhausted?

        last = nil
        MAX_ATTEMPTS.times do |n|
          resp = yield
          outcome = classify(resp)
          return outcome unless outcome.nil?

          last = resp
          # No reintentar si ya no queda presupuesto: prolongar la espera solo empeora el
          # bloqueo del request que está esperando.
          return timed_out_result if budget_exhausted?

          sleep(backoff(n)) unless n == MAX_ATTEMPTS - 1
        end
        Result.new(success: false, error: error_message(last), status: last&.dig(:status))
      end

      # Devuelve el Result definitivo para esta respuesta, o nil si procede reintentar.
      def classify(resp)
        return build_result(resp) if resp[:status] == 200

        raise BudgetExceededError, resp[:body_text] if budget_exceeded?(resp)
        return nil if transient?(resp[:status])

        Result.new(success: false, error: error_message(resp), status: resp[:status])
      end

      def timed_out_result
        Result.new(success: false, status: 504,
                   error: 'El proveedor de IA tardó demasiado en responder. Inténtalo de nuevo.')
      end

      # Reloj monotónico: no se ve afectado por cambios de hora del sistema.
      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def budget_exceeded?(resp)
        return false unless resp[:status] == 429

        text = resp[:body_text].to_s.downcase
        text.include?('budget') || text.include?('exceeded')
      end

      def transient?(status)
        status == 429 || (status && status >= 500)
      end

      def backoff(attempt)
        2**attempt
      end

      def build_result(resp)
        Result.new(success: true, data: resp[:body], status: 200)
      end

      def error_message(resp)
        return 'Sin respuesta del proveedor.' if resp.nil?

        body = resp[:body]
        msg = body.is_a?(Hash) ? (body['error'] || body['message'] || body['detail']) : nil
        redact_secrets("El proveedor respondió #{resp[:status]}#{": #{msg}" if msg.present?}")
      end

      # Elimina cualquier Bearer/master key que un proveedor mal configurado pudiera reflejar
      # en el cuerpo de error, para que el secreto NUNCA llegue a un flash, log o BD.
      def redact_secrets(text)
        out = text.to_s.gsub(/Bearer\s+\S+/i, 'Bearer [REDACTED]')
        key = @config&.master_key_jabvox.to_s
        out = out.gsub(key, '[REDACTED]') if key.present?
        out
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
