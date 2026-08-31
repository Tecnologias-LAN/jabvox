# frozen_string_literal: true

# integration.graphql — consulta/mutación GraphQL por POST. Falla si el status
# es >= 400 O si el cuerpo trae `errors`, que en GraphQL llegan con un 200.
class Jabvox::Flows::Nodes::Integration::GraphqlNode < Jabvox::Flows::Nodes::Integration::Base
  type 'integration.graphql'
  label 'GraphQL'

  def perform
    query = param(:query).to_s.strip
    fail_with!('Falta la consulta GraphQL: rellena el campo "Query/Mutation" del paso.') if query.empty?

    result = http_call(method: 'POST', url: param(:url), headers: param(:headers),
                       body: { 'query' => query, 'variables' => hash_param(param(:variables)) })
    output = { 'status' => result['status'], 'data' => result['data'] }

    if graphql_errors?(result['data'])
      return Jabvox::Flows::Engine::NodeResult.new(ok: false, output: output,
                                                   error: 'GraphQL devolvió errores.')
    end

    with_status(output, result['status'])
  end

  private

  def graphql_errors?(data)
    data.is_a?(Hash) && data['errors'].present?
  end
end
