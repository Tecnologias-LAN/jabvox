# frozen_string_literal: true

# Adaptador MOCK en memoria del proveedor de IA. Se usa en dev/test cuando el proveedor real
# no está configurado, para verificar el flujo completo (crear team, consultar, recargar,
# bloquear, generar keys) sin llamar al proxy. Emula las reglas clave: max_budget es tope
# absoluto, el spend se acumula, y un team agotado responde 429 con "budget exceeded".
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module AiProvider
    class MockAdapter
      def self.instance
        @instance ||= new
      end

      # Reinicia el estado (útil entre tests).
      def self.reset!
        @instance = new
      end

      def initialize
        @teams = {}
        @keys = {}
        @seq = 0
      end

      def request(method, path, params: nil, body: nil) # rubocop:disable Metrics/CyclomaticComplexity
        key = "#{method.to_s.upcase} #{path}"
        args = (body || params || {}).transform_keys(&:to_s)
        case key
        when 'POST /team/new'       then create_team(args)
        when 'GET /team/info'       then team_info(args)
        when 'POST /team/update'    then update_team(args)
        when 'POST /team/block'     then set_team_block(args, true)
        when 'POST /team/unblock'   then set_team_block(args, false)
        when 'GET /team/daily/activity' then activity(args)
        when 'POST /key/generate'   then generate_key(args)
        when 'GET /key/info'        then key_info(args)
        when 'GET /key/list'        then list_keys(args)
        when 'POST /key/block'      then set_key_block(args, true)
        when 'POST /key/unblock'    then set_key_block(args, false)
        when 'GET /model/info'      then ok('data' => [{ 'model_name' => 'mock/model-a' }, { 'model_name' => 'mock/model-b' }])
        else not_found("ruta desconocida: #{key}")
        end
      end

      private

      def ok(body) = { status: 200, body: body, body_text: body.to_json }
      def not_found(msg) = { status: 404, body: { 'error' => msg }, body_text: msg }

      def create_team(args)
        @seq += 1
        id = "team-mock-#{@seq}"
        @teams[id] = { 'team_id' => id, 'team_alias' => args['team_alias'],
                       'max_budget' => args['max_budget'], 'spend' => 0.0,
                       'blocked' => false, 'metadata' => args['metadata'] || {} }
        ok(@teams[id].merge('team_id' => id))
      end

      def team_info(args)
        t = @teams[args['team_id']]
        return not_found('team no existe') unless t

        ok('team_info' => t)
      end

      def update_team(args)
        t = @teams[args['team_id']]
        return not_found('team no existe') unless t

        t['max_budget'] = args['max_budget']
        ok('team_info' => t)
      end

      def set_team_block(args, blocked)
        t = @teams[args['team_id']]
        return not_found('team no existe') unless t

        t['blocked'] = blocked
        ok('team_info' => t)
      end

      def activity(args)
        t = @teams[args['team_id']]
        return not_found('team no existe') unless t

        ok('results' => [], 'metadata' => { 'total_spend' => t['spend'] })
      end

      def generate_key(args)
        @seq += 1
        k = "sk-mock-#{@seq}"
        @keys[k] = { 'key_alias' => args['key_alias'], 'team_id' => args['team_id'], 'token_id' => "tok-#{@seq}",
                     'max_budget' => args['max_budget'], 'spend' => 0.0, 'blocked' => false }
        ok('key' => k, 'token_id' => "tok-#{@seq}")
      end

      # Lista las keys del team (metadatos, NUNCA la key en claro — como el proveedor real).
      def list_keys(args)
        rows = @keys.values.select { |v| v['team_id'] == args['team_id'] }
                    .map { |v| v.except('team_id') }
        ok('keys' => rows)
      end

      def key_info(args)
        info = @keys[args['key']]
        return not_found('key no existe') unless info

        ok('info' => info)
      end

      def set_key_block(args, blocked)
        info = @keys[args['key']]
        return not_found('key no existe') unless info

        info['blocked'] = blocked
        ok('info' => info)
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
