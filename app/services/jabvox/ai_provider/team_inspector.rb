# frozen_string_literal: true

# Diagnóstico de un team en el proveedor (Super Admin): qué virtual keys devuelve realmente
# y a qué team pertenece cada una. Sirve para entender por qué una key creada directamente
# en el proveedor no aparece en la pantalla de una cuenta.
#
# NUNCA expone la key en claro: solo un prefijo del hash, suficiente para identificarla.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module AiProvider
    class TeamInspector
      # Nº de caracteres del hash que se muestran. Suficiente para distinguir keys sin
      # revelar el valor completo.
      TOKEN_PREVIEW = 12

      def initialize(client: nil, config: nil)
        @config = config || JabvoxAiProviderConfig.instance
        @client = client || Jabvox::AiProvider::Client.new(config: @config)
      end

      def call(team_id)
        return { error: 'El proveedor no está configurado.' } unless @config.configured?

        id = team_id.to_s
        resp = @client.list_keys(id)
        return { error: resp.error } unless resp.success?

        build(id, resp.data)
      rescue StandardError => e
        Rails.logger.error("[AiProvider::TeamInspector] #{e.class}: #{e.message}")
        { error: 'No se pudo consultar el proveedor.' }
      end

      private

      def build(team_id, data)
        hash = data.is_a?(Hash)
        rows = hash ? Array(data['keys']) : Array(data)
        { team_id: team_id,
          total_count: hash ? data['total_count'] : rows.size,
          total_pages: hash ? data['total_pages'] : 1,
          team_models: team_models(team_id),
          keys: rows.map { |k| key_row(k) } }
      end

      def team_models(team_id)
        resp = @client.team_info(team_id)
        resp.success? ? Array(resp.data.dig('team_info', 'models')).map(&:to_s) : []
      end

      def key_row(key)
        return { alias: '(respuesta no estructurada)', token: key.to_s[0, TOKEN_PREVIEW] } unless key.is_a?(Hash)

        { alias: key['key_alias'], team_id: key['team_id'],
          models: Array(key['models']).map(&:to_s),
          spend: key['spend'], max_budget: key['max_budget'], blocked: key['blocked'],
          token: key['token'].to_s[0, TOKEN_PREVIEW] }
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
