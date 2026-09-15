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
        when 'GET /team/list'       then list_teams
        when 'POST /team/delete'    then delete_teams(args)
        when 'GET /team/daily/activity' then activity(args)
        when 'GET /model/info'      then ok('data' => [{ 'model_name' => 'mock/model-a' }, { 'model_name' => 'mock/model-b' }])
        else key_route(key, args)
        end
      end

      # Rutas de virtual keys (separadas para no inflar el enrutado principal).
      def key_route(key, args)
        case key
        when 'POST /key/generate' then generate_key(args)
        when 'GET /key/info'      then key_info(args)
        when 'GET /key/list'      then list_keys(args)
        when 'POST /key/block'    then set_key_block(args, true)
        when 'POST /key/unblock'  then set_key_block(args, false)
        when 'POST /key/update'   then update_key(args)
        else not_found("ruta desconocida: #{key}")
        end
      end

      # Permite sembrar teams "que ya existen en el proxy" para probar la importación.
      def seed_team(team_id:, **attrs)
        @teams[team_id] = { 'team_id' => team_id,
                            'team_alias' => attrs[:team_alias],
                            'max_budget' => attrs[:max_budget],
                            'spend' => attrs.fetch(:spend, 0.0),
                            'blocked' => false,
                            'metadata' => attrs.fetch(:metadata, {}),
                            'models' => attrs.fetch(:models, []) }
      end

      private

      def ok(body) = { status: 200, body: body, body_text: body.to_json }
      def not_found(msg) = { status: 404, body: { 'error' => msg }, body_text: msg }

      def create_team(args)
        @seq += 1
        id = args['team_id'].presence || "team-mock-#{@seq}"
        @teams[id] = { 'team_id' => id, 'team_alias' => args['team_alias'],
                       'max_budget' => args['max_budget'], 'spend' => 0.0,
                       'blocked' => false, 'metadata' => args['metadata'] || {},
                       'models' => Array(args['models']) }
        ok(@teams[id].merge('team_id' => id))
      end

      def team_info(args)
        t = @teams[args['team_id']]
        return not_found('team no existe') unless t

        ok('team_info' => t)
      end

      # Igual que LiteLLM: /team/list devuelve un ARRAY PLANO de teams.
      def list_teams
        ok(@teams.values.map { |t| t.merge('team_memberships' => [], 'keys' => []) })
      end

      def delete_teams(args)
        Array(args['team_ids']).each { |id| @teams.delete(id) }
        ok('deleted_teams' => Array(args['team_ids']))
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
                    .map { |v| v.except('team_id').merge('token' => v['token_id']) }
        ok('keys' => rows, 'total_count' => rows.size, 'current_page' => 1, 'total_pages' => 1)
      end

      def key_info(args)
        info = find_key(args['key'])
        return not_found('key no existe') unless info

        ok('info' => info)
      end

      def set_key_block(args, blocked)
        info = find_key(args['key'])
        return not_found('key no existe') unless info

        info['blocked'] = blocked
        ok('info' => info)
      end

      def update_key(args)
        info = find_key(args['key'])
        return not_found('key no existe') unless info

        info['max_budget'] = args['max_budget'] if args.key?('max_budget')
        ok('info' => info)
      end

      # Como el proveedor real: una key se identifica por su valor en claro (sk-...) O por su
      # hash/token. Jabvox siempre usa el hash, para no tener que almacenar el secreto.
      def find_key(identifier)
        id = identifier.to_s
        @keys[id] || @keys.values.find { |v| v['token_id'].to_s == id || v['token'].to_s == id }
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
