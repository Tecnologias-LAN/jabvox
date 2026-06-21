require 'csv'

# Renders a dashboard's widget data to PDF / Excel / CSV. Each widget's query is re-run with
# the requesting user's data permissions (via QueryExecutionService), so a share can't leak
# data the user couldn't otherwise see. Returns the file bytes + content type + filename.
class Jabvox::Analytics::ExportService
  Output = Struct.new(:bytes, :content_type, :filename, keyword_init: true)

  def initialize(export)
    @export = export
    @dashboard = export.dashboard
    @user = export.user
    @account = export.account
  end

  def call
    datasets = collect_datasets
    case @export.format_jabvox
    when 'csv' then build_csv(datasets)
    when 'excel' then build_excel(datasets)
    when 'pdf' then build_pdf(datasets)
    else raise ArgumentError, "Formato no soportado: #{@export.format_jabvox}"
    end
  end

  private

  # [{ title:, columns:, rows: }] — one per widget that has a data source.
  def collect_datasets
    @dashboard.widgets.ordered.filter_map do |widget|
      next unless widget.data_source

      resolver = Jabvox::Analytics::PermissionResolver.new(@user, @account)
      next unless resolver.can_access_data_source?(widget.data_source)

      result = execute_widget(widget)
      { title: widget.title_jabvox.presence || widget.widget_type_jabvox, columns: result.columns, rows: result.rows }
    rescue StandardError => e
      Rails.logger.error "[Analytics::Export] widget #{widget.id} failed: #{e.message}"
      nil
    end
  end

  def execute_widget(widget)
    svc = Jabvox::Analytics::QueryExecutionService.new(data_source: widget.data_source, user: @user)
    widget.uses_custom_sql? ? svc.run_custom_sql(widget.custom_sql_jabvox) : svc.run_visual(widget.query_spec_jabvox)
  end

  def base_filename
    "#{@dashboard.name_jabvox.parameterize}-#{@dashboard.id}"
  end

  def build_csv(datasets)
    content = CSV.generate do |csv|
      datasets.each do |ds|
        csv << ["# #{ds[:title]}"]
        csv << ds[:columns]
        ds[:rows].each { |row| csv << row }
        csv << []
      end
    end
    Output.new(bytes: content, content_type: 'text/csv', filename: "#{base_filename}.csv")
  end

  def build_excel(datasets)
    package = Axlsx::Package.new
    wb = package.workbook
    datasets.each_with_index do |ds, idx|
      name = ds[:title].to_s.gsub(/[^a-zA-Z0-9 ]/, '').slice(0, 28).presence || "Hoja #{idx + 1}"
      wb.add_worksheet(name: "#{name} #{idx + 1}") do |sheet|
        sheet.add_row ds[:columns]
        ds[:rows].each { |row| sheet.add_row row }
      end
    end
    Output.new(bytes: package.to_stream.read, content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
               filename: "#{base_filename}.xlsx")
  end

  def build_pdf(datasets)
    Prawn::Fonts::AFM.hide_m17n_warning = true
    pdf = Prawn::Document.new(page_layout: :landscape)
    pdf.text @dashboard.name_jabvox, size: 18, style: :bold
    pdf.move_down 12
    datasets.each { |ds| render_pdf_section(pdf, ds) }
    Output.new(bytes: pdf.render, content_type: 'application/pdf', filename: "#{base_filename}.pdf")
  end

  def render_pdf_section(pdf, dataset)
    pdf.text dataset[:title].to_s, size: 13, style: :bold
    pdf.move_down 4
    if dataset[:rows].any?
      table_data = [dataset[:columns]] + dataset[:rows].map { |r| r.map { |c| c.to_s.slice(0, 40) } }
      pdf.table(table_data, header: true, width: pdf.bounds.width, cell_style: { size: 8, padding: 4 })
    else
      pdf.text 'Sin datos', size: 9, style: :italic
    end
    pdf.move_down 16
  end
end
