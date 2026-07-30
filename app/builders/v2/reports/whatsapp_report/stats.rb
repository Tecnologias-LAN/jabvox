# Numeric helpers for the WhatsApp report: median/avg/p90, rates, and the
# row/ranking sort keys. Pure functions of their inputs; split out of the builder
# to keep it focused.
module V2::Reports::WhatsappReport::Stats
  def time_stats(values)
    return { avg: nil, median: nil, p90: nil, count: 0 } if values.blank?

    sorted = values.sort
    { avg: (values.sum.to_f / values.size).round, median: percentile(sorted, 50),
      p90: percentile(sorted, 90), count: values.size }
  end

  def percentile(sorted, pct)
    return sorted.first if sorted.size == 1

    rank = (pct / 100.0) * (sorted.size - 1)
    lower = sorted[rank.floor]
    upper = sorted[rank.ceil]
    (lower + ((upper - lower) * (rank - rank.floor))).round
  end

  def rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    ((numerator.to_f / denominator) * 100).round(1)
  end

  def sort_rows(rows)
    key = params[:sort_by].presence&.to_sym
    return rows unless key && rows.first&.key?(key)

    sorted = rows.sort_by { |r| sortable(r[key]) }
    params[:order].to_s == 'asc' ? sorted : sorted.reverse
  end

  def sortable(value)
    value.is_a?(Hash) ? (value[:median] || -1) : (value || -1)
  end

  # Extracts a comparable number from a metric that may be a time_stats hash.
  def ranking_value(value)
    value.is_a?(Hash) ? value[:median] : value
  end

  def ranking_key(metric)
    {
      'first_response' => :first_response, 'first_read' => :time_to_read,
      'read_rate' => :read_rate, 'resolution' => :resolution,
      'volume' => :sent, 'sla' => :sla_pct
    }.fetch(metric.to_s, :sent)
  end

  def range
    return nil if params[:from].blank? || params[:to].blank?

    Time.zone.at(params[:from].to_i)..Time.zone.at(params[:to].to_i)
  end

  def sla_seconds
    params[:sla_seconds].presence&.to_i || V2::Reports::WhatsappAgentReportBuilder::DEFAULT_SLA
  end

  def sla_pct(uid)
    values = reporting_values('first_response', uid)
    return nil if values.empty?

    within = values.count { |v| v <= sla_seconds }
    ((within.to_f / values.size) * 100).round(1)
  end

  def csat_avg
    @csat_avg ||= account.csat_survey_responses
                         .where(conversation_id: conversation_ids)
                         .group(:assigned_agent_id).average(:rating)
                         .transform_values { |v| v.to_f.round(2) }
  end
end
