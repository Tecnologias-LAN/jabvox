# Cross-source reports API: CRUD for reports that join data across several data
# sources (e.g. Wimpos' 4 SQL Server databases on different servers) plus execution.
# Managing (create/update/destroy) requires manage_data_sources; running requires
# analytics access (same gate as viewing data).
class Api::V1::Accounts::Jabvox::Analytics::CrossReportsController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :set_report, only: %i[show update destroy execute]
  before_action :authorize_manage!, only: %i[create update destroy]

  def index
    reports = scoped_reports.order(:name_jabvox)
    render json: reports.map { |r| serialize(r, full: false) }
  end

  def show
    render json: serialize(@report, full: true)
  end

  def create
    report = scoped_reports.new(report_params)
    report.account = Current.account
    report.created_by = current_user
    if save_with_children(report)
      audit!(action: 'cross_report.create', auditable: report, metadata: { name: report.name_jabvox })
      render json: serialize(report, full: true), status: :created
    else
      render json: { errors: report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if save_with_children(@report, report_params)
      audit!(action: 'cross_report.update', auditable: @report)
      render json: serialize(@report, full: true)
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @report.destroy
    audit!(action: 'cross_report.destroy', auditable: @report)
    head :no_content
  end

  # Runs the cross-source join and returns the result rows/columns.
  def execute
    result = Jabvox::Analytics::CrossReportExecutionService.new(@report).call
    render json: {
      columns: result.columns, rows: result.rows, row_count: result.row_count,
      truncated: result.truncated, sources: result.sources
    }
  rescue Jabvox::Analytics::CrossReportExecutionService::ExecutionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def scoped_reports
    JabvoxAnalyticsCrossReport.where(account_id: Current.account.id)
                              .includes(:cross_sources, :cross_joins)
  end

  def set_report
    @report = scoped_reports.find(params[:id])
  end

  def authorize_manage!
    authorize!(:manage_data_sources)
  end

  # Replaces the report's sources/joins atomically with the submitted set, so the
  # visual editor can save the whole graph in one call. Rebuilt inside a transaction
  # so a bad join never leaves a half-saved report.
  def save_with_children(report, attrs = nil)
    ActiveRecord::Base.transaction do
      report.assign_attributes(attrs) if attrs
      report.save!
      rebuild_sources(report)
      rebuild_joins(report)
      true
    end
  rescue ActiveRecord::RecordInvalid => e
    report.errors.add(:base, e.message) if report.errors.empty?
    false
  end

  def rebuild_sources(report)
    return if params[:sources].nil?

    report.cross_sources.destroy_all
    Array(params[:sources]).each_with_index do |s, i|
      report.cross_sources.create!(
        data_source_id: resolve_data_source_id(s[:data_source_id]),
        table_jabvox: s[:table], alias_jabvox: s[:alias],
        columns_jabvox: Array(s[:columns]), filters_jabvox: normalize_filters(s[:filters]),
        position_jabvox: i
      )
    end
  end

  def rebuild_joins(report)
    return if params[:joins].nil?

    report.cross_joins.destroy_all
    by_alias = report.cross_sources.index_by(&:alias_jabvox)
    Array(params[:joins]).each_with_index do |j, i|
      left = by_alias[j[:left_alias]]
      right = by_alias[j[:right_alias]]
      next unless left && right

      report.cross_joins.create!(
        left_source: left, left_column_jabvox: j[:left_column],
        right_source: right, right_column_jabvox: j[:right_column],
        join_type_jabvox: (j[:join_type].presence || 'inner'), position_jabvox: i
      )
    end
  end

  # Only allow data sources that belong to THIS account (tenant isolation).
  def resolve_data_source_id(id)
    JabvoxAnalyticsDataSource.where(account_id: Current.account.id).find(id).id
  end

  def normalize_filters(filters)
    Array(filters).filter_map do |f|
      next if f[:column].blank?

      { 'column' => f[:column], 'operator' => f[:operator], 'value' => f[:value] }
    end
  end

  def report_params
    params.permit(:name_jabvox, :description_jabvox, :row_limit_jabvox)
  end

  def serialize(report, full:)
    data = {
      id: report.id, name_jabvox: report.name_jabvox, description_jabvox: report.description_jabvox,
      row_limit_jabvox: report.row_limit_jabvox, sources_count: report.cross_sources.size,
      updated_at: report.updated_at
    }
    return data unless full

    data.merge(
      sources: report.cross_sources.sort_by(&:position_jabvox).map { |s| serialize_source(s) },
      joins: report.cross_joins.sort_by(&:position_jabvox).map { |j| serialize_join(j, report) }
    )
  end

  def serialize_source(src)
    {
      id: src.id, data_source_id: src.data_source_id,
      data_source_name: src.data_source&.name_jabvox, table: src.table_jabvox,
      alias: src.alias_jabvox, columns: src.columns_jabvox, filters: src.filters_jabvox
    }
  end

  def serialize_join(join, report)
    by_id = report.cross_sources.index_by(&:id)
    {
      id: join.id,
      left_alias: by_id[join.left_source_id]&.alias_jabvox, left_column: join.left_column_jabvox,
      right_alias: by_id[join.right_source_id]&.alias_jabvox, right_column: join.right_column_jabvox,
      join_type: join.join_type_jabvox
    }
  end
end
