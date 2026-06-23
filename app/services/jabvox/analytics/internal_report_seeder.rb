# Creates one dashboard per selected built-in report, with a full set of
# widgets (KPI cards from summary + a time-series line + bar/table widgets per
# breakdown). Each widget carries config_jabvox['report_key'] plus a 'section'
# or 'metric' so the executor knows which slice of the report to render.
# Widgets have no data source — they run the pre-baked Ruby service scoped to
# the account. Idempotent by dashboard name within the account.
class Jabvox::Analytics::InternalReportSeeder
  FOLDER_NAME = 'Reportes'.freeze
  GRID_COLS = 24

  def initialize(account:, user: nil, keys: [])
    @account = account
    @user = user
    @keys = Array(keys).select { |k| Jabvox::Analytics::InternalReportCatalog.exists?(k) }
  end

  def call
    return [] if @keys.empty?

    folder = find_or_create_folder
    catalog = Jabvox::Analytics::InternalReportCatalog.all.index_by { |r| r[:key] }
    @keys.map { |key| build_dashboard(key, catalog[key], folder) }
  end

  private

  attr_reader :account, :user

  def find_or_create_folder
    account.jabvox_analytics_folders.find_or_create_by!(name_jabvox: FOLDER_NAME) do |f|
      f.created_by_id = user&.id
      f.position_jabvox = 0
    end
  end

  def build_dashboard(key, entry, folder)
    label = entry[:label]
    existing = account.jabvox_analytics_dashboards.find_by(name_jabvox: label)
    return existing if existing

    widgets = widget_specs(key)
    dashboard = account.jabvox_analytics_dashboards.create!(
      name_jabvox: label,
      description_jabvox: "Reporte interno: #{label} (datos de esta cuenta)",
      folder_id: folder.id,
      created_by_id: user&.id,
      global_filters_jabvox: {},
      cache_ttl_seconds_jabvox: 300,
      layout_jabvox: widgets.each_with_index.map { |w, i| w[:grid].merge(i: i) }
    )
    create_widgets(dashboard, widgets)
    dashboard
  end

  def create_widgets(dashboard, widgets)
    widgets.each_with_index do |w, idx|
      dashboard.widgets.create!(
        account_id: account.id,
        widget_type_jabvox: w[:type],
        title_jabvox: w[:title],
        position_jabvox: idx,
        query_spec_jabvox: {},
        config_jabvox: w[:config]
      )
    end
  end

  # Build the ordered widget list (KPIs row, series line, breakdown bars/tables)
  # from the report's declared layout. Falls back to a single summary table.
  def widget_specs(key)
    layout = Jabvox::Analytics::InternalReportLayout.for(key)
    return [summary_table(key)] unless layout

    kpis = layout[:kpis] || []
    specs = kpi_widgets(key, kpis)
    y = kpis.any? ? 3 : 0

    if layout[:series]
      specs << line_widget(key, y)
      y += 6
    end

    specs + section_widgets(key, layout[:sections] || [], y)
  end

  def kpi_widgets(key, kpis)
    return [] if kpis.empty?

    width = [GRID_COLS / kpis.size, 6].min
    kpis.each_with_index.map do |(metric, label), i|
      {
        type: 'number', title: label,
        config: { 'report_key' => key, 'metric' => metric },
        grid: { x: (i * width) % GRID_COLS, y: 0, w: width, h: 3 }
      }
    end
  end

  def line_widget(key, start_y)
    {
      type: 'line', title: 'Evolución por día',
      config: { 'report_key' => key, 'section' => 'series' },
      grid: { x: 0, y: start_y, w: GRID_COLS, h: 6 }
    }
  end

  def section_widgets(key, sections, base_y)
    half = GRID_COLS / 2
    specs = []
    sections.each_slice(2).with_index do |pair, row|
      pair.each_with_index do |(section, title, type), col|
        specs << {
          type: type, title: title,
          config: { 'report_key' => key, 'section' => section },
          grid: { x: col * half, y: base_y + (row * 7), w: half, h: 7 }
        }
      end
    end
    specs
  end

  def summary_table(key)
    {
      type: 'table', title: 'Resumen',
      config: { 'report_key' => key, 'section' => 'summary' },
      grid: { x: 0, y: 0, w: GRID_COLS, h: 10 }
    }
  end
end
