# frozen_string_literal: true

# Per-agent drill-down for the agents report (messages, notes, managements,
# orders, calls), each with metric-specific filters and a totals breakdown.
# Reuses the reports gating: no single module flag (jabvox_feature :none) plus
# the per-account jabvox_reports_view permission.
#
#   GET .../jabvox/reports/analytics/:metric_key/records
#   GET .../jabvox/reports/analytics/:metric_key/breakdown  (totals + filter options)
class Api::V1::Accounts::Jabvox::Reports::AnalyticsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  jabvox_feature :none
  before_action -> { jabvox_authorize!('jabvox_reports_view') }
  before_action :set_range
  before_action :set_metric

  rescue_from Jabvox::Reports::RangeTooLargeError do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def records
    result = Jabvox::Reports::RecordsService.new(
      account: Current.account,
      definition: @metric,
      range: @range,
      filters: filters,
      cursor: params[:cursor],
      per_page: params[:per_page],
      order_dir: params[:order_dir]
    ).call

    render json: {
      data: result.data,
      meta: {
        total_count: result.total_count,
        total_is_approx: result.total_is_approx,
        next_cursor: result.next_cursor,
        has_more: result.has_more,
        metric: { key: @metric[:key], label: @metric[:label] }
      }
    }
  end

  # Totals breakdown (respects the active filters) + the filter definitions and
  # their option lists (management states, products) so the UI can render the
  # metric-specific filter controls.
  def breakdown
    result = Jabvox::Reports::BreakdownService.new(
      account: Current.account, definition: @metric, range: @range, filters: filters
    ).call

    render json: {
      total: result[:total],
      rows: result[:rows],
      breakdown_label: @metric.dig(:breakdown, :label),
      filters_config: @metric[:filters_config] || [],
      filter_options: filter_options
    }
  end

  private

  def set_range
    @range = Jabvox::Reports::TimeRange.new(
      account: Current.account,
      preset: params[:preset],
      from: params[:from],
      to: params[:to]
    )
  end

  def set_metric
    @metric = Jabvox::Reports::MetricRegistry.find(params[:metric_key])
    render(json: { error: 'Métrica desconocida' }, status: :not_found) unless @metric
  end

  def filters
    {
      inbox_ids: Array(params[:inbox_ids]),
      agent_ids: Array(params[:agent_ids]),
      search: params[:search],
      status: Array(params[:status]),
      management_state_id: params[:management_state_id],
      doc_type: params[:doc_type],
      product_id: params[:product_id],
      call_status: params[:call_status]
    }.compact_blank
  end

  # Option lists needed by this metric's select filters.
  def filter_options
    sources = (@metric[:filters_config] || []).filter_map { |f| f[:options_source] }
    opts = {}
    if sources.include?('management_states')
      opts[:management_states] = Current.account.jabvox_management_states.ordered
                                        .map { |s| { value: s.id, label: s.name_jabvox } }
    end
    if sources.include?('products')
      opts[:products] = Current.account.jabvox_products.order(:name_jabvox)
                               .limit(500).map { |p| { value: p.id, label: p.name_jabvox } }
    end
    opts
  end
end
