# frozen_string_literal: true

# Cuenta las tablas y vistas de una fuente de datos.
#
# Lee el esquema YA cacheado por IntrospectionService, así que no añade ni una consulta a la
# base del cliente: es solo para mostrar el número junto a "Ver tablas".
class Jabvox::Analytics::SchemaStats
  def initialize(data_source)
    @data_source = data_source
  end

  def call
    nodes = schema_nodes
    views = nodes.count { |n| node_type(n) == 'view' }
    { tables: nodes.size - views, views: views, total: nodes.size }
  end

  private

  # El esquema llega como array plano o como hash agrupando tablas y vistas.
  def schema_nodes
    schema = Jabvox::Analytics::IntrospectionService.new(@data_source).call
    return Array(schema) unless schema.is_a?(Hash)

    Array(schema[:tables]) + Array(schema[:views])
  end

  def node_type(node)
    node.is_a?(Hash) ? (node[:type] || node['type']).to_s : ''
  end
end
