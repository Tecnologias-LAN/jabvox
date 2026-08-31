# frozen_string_literal: true

# jabvox.lead.find_by_date — legacy (oculto): misma lógica que
# jabvox.lead.search modo by_date, con la salida original
# `{ entity, field, targetDate, leads, count }`.
class Jabvox::Flows::Nodes::Jabvox::LeadFindByDateNode < Jabvox::Flows::Nodes::Jabvox::LeadSearchNode
  type 'jabvox.lead.find_by_date'
  label 'Buscar leads por campo de fecha'
  items_path 'leads'

  MATCHES = %w[today in_days days_ago].freeze

  def initialize(ctx, node, params)
    # El nodo unificado solo SUMA días; aquí el `match` legacy decide el signo,
    # así que se normaliza el offset antes de que `by_date` lo lea.
    super
    @params = @params.merge('offsetDays' => signed_offset)
  end

  def perform
    found = by_date
    { 'entity' => 'lead', 'field' => found['field'], 'targetDate' => found['targetDate'],
      'compareMode' => found['compareMode'], 'leads' => found['leads'], 'count' => found['count'] }
  end

  private

  def signed_offset
    match = first_filled(@params['match'], 'today')
    match = 'today' unless MATCHES.include?(match)
    return 0 if match == 'today'

    days = int_or(@params['offsetDays'], 0).abs
    match == 'days_ago' ? -days : days
  end
end
