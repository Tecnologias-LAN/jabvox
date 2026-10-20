require 'prawn'
require 'prawn/table'

# Genera el PDF de evaluación de calidad de UNA llamada, replicando el layout del
# documento de referencia "Reporte Final": cabecera con datos de la llamada,
# tabla de infaltables (resultado + evidencia + momento), tabla de anatomía y
# el resumen de cumplimiento. Usa Prawn (fuentes AFM, sin emojis: el estado se
# muestra con texto y color de celda).
# Código de maquetación de PDF: los métodos de render son verbosos por naturaleza
# (tablas, estilos, posicionamiento), de ahí los disables de métricas.
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
class Jabvox::AudioQaReportPdfService
  # Colores por estado (hex sin #).
  GREEN = 'D6F5DD'.freeze
  RED = 'FBD9D9'.freeze
  GRAY = 'EDEDED'.freeze
  YELLOW = 'FDF3D0'.freeze

  def initialize(result)
    @result = result
    @typification = result.typification
    @advisor_name = result.advisor&.name || result.assigned_agent&.name || '—'
  end

  # Devuelve los bytes del PDF.
  def render
    Prawn::Fonts::AFM.hide_m17n_warning = true
    pdf = Prawn::Document.new(page_size: 'A4', margin: 36)

    header(pdf)
    summary_box(pdf)
    second_validation(pdf)
    infaltables_table(pdf)
    anatomy_table(pdf)
    findings(pdf)

    pdf.render
  end

  # Bloque de la segunda validación (auditoría), cuando se ejecutó.
  def second_validation(pdf)
    return if @result.review_explanation.blank?

    pdf.text 'Segunda validación (auditoría)', size: 12, style: :bold
    pdf.move_down 2
    if @result.first_pass_score.present?
      pdf.text safe("1ª validación: #{@result.first_pass_score}%  ->  resultado final: #{@result.infaltables_score}%"),
               size: 9, style: :italic
      pdf.move_down 2
    end
    pdf.text safe(@result.review_explanation.to_s), size: 9
    pdf.move_down 12
  end

  # La fuente AFM de Prawn solo soporta Windows-1252; el texto que genera la IA
  # puede traer flechas, emojis o símbolos fuera de ese set. Los reemplaza para no
  # romper el render (usar una fuente TTF embebida sería la alternativa completa).
  def safe(text)
    text.to_s
        .gsub('→', '->').gsub('←', '<-').tr('•', '-').gsub('✅', '[OK]').gsub('❌', '[X]')
        .encode('Windows-1252', invalid: :replace, undef: :replace, replace: '')
        .encode('UTF-8')
  end

  def filename
    base = @result.file_key.to_s.split('/').last.to_s.sub(/\.[^.]+\z/, '')
    "reporte-qa-#{base.parameterize.presence || @result.id}.pdf"
  end

  private

  def header(pdf)
    pdf.text 'Evaluación de calidad — Análisis de llamada', size: 16, style: :bold
    pdf.move_down 8
    meta = [
      ['Asesor', @advisor_name, 'Teléfono', @result.parsed_metadata['phone'] || '—'],
      ['Tipificación asignada', @typification&.name || '—', 'Tipificación detectada', @result.detected_typification&.name || '—'],
      ['ID de llamada', @result.parsed_metadata['call_id'] || @result.id.to_s, 'Archivo', @result.file_key.to_s.split('/').last]
    ]
    pdf.table(meta, width: pdf.bounds.width, cell_style: { size: 9, padding: 5 }) do
      columns(0).font_style = :bold
      columns(2).font_style = :bold
      columns(0).background_color = GRAY
      columns(2).background_color = GRAY
    end
    pdf.move_down 6
    # Nota de re-tipificación: "tipificada como X pero se asemeja más a Y porque…".
    pdf.text safe("Nota de tipificación: #{@result.retypification_reason}"), size: 8, style: :italic if @result.retypification_reason.present?
    pdf.move_down 10
  end

  def summary_box(pdf)
    score = @result.infaltables_score
    label = score.nil? ? 'Sin score' : "#{score}%"
    review = @result.review_status == 'en_revision' ? '  •  EN REVISIÓN' : ''
    data = [[
      "Infaltables aplicables: #{@result.infaltables_applicable || '—'}",
      "Cumplidos: #{@result.infaltables_met || '—'}",
      "Cumplimiento: #{label}#{review}"
    ]]
    # El color se calcula fuera del bloque: prawn-table ejecuta el bloque con
    # instance_eval sobre la tabla, donde @result no existe.
    box_color = @result.review_status == 'en_revision' ? RED : GREEN
    pdf.table(data, width: pdf.bounds.width, cell_style: { size: 10, padding: 6, font_style: :bold }) do
      cells.background_color = box_color
    end
    pdf.move_down 14
  end

  def infaltables_table(pdf)
    rows = Array(@result.infaltables_result)
    return if rows.empty?

    pdf.text 'Infaltables', size: 12, style: :bold
    pdf.move_down 4
    head = ['#', 'Infaltable', 'Resultado', 'Evidencia', 'Momento']
    body = rows.each_with_index.map do |r, i|
      [format('%02d', i + 1), safe(item_text(r)), status_label(r['status']), safe(r['evidence'].to_s), safe(r['timestamp'].to_s)]
    end
    # Colores precalculados fuera del bloque (instance_eval no ve métodos propios).
    colors = rows.map { |r| status_color(r['status']) }
    gray = GRAY
    pdf.table([head] + body, width: pdf.bounds.width, header: true,
                             column_widths: [22, 150, 70, nil, 50], cell_style: { size: 8, padding: 4 }) do
      row(0).font_style = :bold
      row(0).background_color = gray
      colors.each_with_index { |color, i| row(i + 1).column(2).background_color = color }
    end
    pdf.move_down 14
  end

  def anatomy_table(pdf)
    rows = Array(@result.anatomy_result)
    return if rows.empty?

    pdf.text 'Anatomía / Cercanía', size: 12, style: :bold
    pdf.move_down 4
    head = %w[Dimensión Resultado Evidencia Momento]
    by_id = anatomy_names
    body = rows.map do |r|
      [safe(by_id[r['id']] || r['name'].to_s), anatomy_label(r['status']), safe(r['evidence'].to_s), safe(r['timestamp'].to_s)]
    end
    colors = rows.map { |r| anatomy_color(r['status']) }
    gray = GRAY
    pdf.table([head] + body, width: pdf.bounds.width, header: true,
                             column_widths: [120, 80, nil, 50], cell_style: { size: 8, padding: 4 }) do
      row(0).font_style = :bold
      row(0).background_color = gray
      colors.each_with_index { |color, i| row(i + 1).column(1).background_color = color }
    end
    pdf.move_down 14
  end

  def findings(pdf)
    summary = @result.qa_summary || {}
    pdf.text 'Resumen y hallazgos', size: 12, style: :bold
    pdf.move_down 4
    pdf.text safe(summary['summary'].to_s), size: 9 if summary['summary'].present?
    pdf.move_down 6
    Array(summary['findings']).each do |f|
      next if f['finding'].to_s.blank?

      pdf.text safe("- #{f['finding']}"), size: 9, style: :bold
      pdf.text safe("  Evidencia: #{f['evidence']}"), size: 8 if f['evidence'].present?
      pdf.text safe("  Momento: #{f['moment']}"), size: 8 if f['moment'].present?
      pdf.text safe("  Oportunidad: #{f['opportunity']}"), size: 8 if f['opportunity'].present?
      pdf.text safe("  Coaching: #{f['coaching']}"), size: 8 if f['coaching'].present?
      pdf.move_down 4
    end
  end

  def item_text(row)
    text = row['text'].to_s
    row['optional'] ? "#{text} (deseable)" : text
  end

  def status_label(status)
    { 'CUMPLE' => 'CUMPLE', 'NO_CUMPLE' => 'NO CUMPLE',
      'NO_APLICA' => 'NO APLICA', 'NO_VERIFICABLE' => 'NO VERIF.' }[status.to_s] || status.to_s
  end

  def status_color(status)
    { 'CUMPLE' => GREEN, 'NO_CUMPLE' => RED, 'NO_APLICA' => GRAY, 'NO_VERIFICABLE' => YELLOW }[status.to_s] || GRAY
  end

  def anatomy_label(status)
    { 'LIKEU' => 'LIKEU', 'OPORTUNIDAD' => 'OPORTUNIDAD', 'NO_VERIFICABLE' => 'NO VERIF.' }[status.to_s] || status.to_s
  end

  def anatomy_color(status)
    { 'LIKEU' => GREEN, 'OPORTUNIDAD' => RED, 'NO_VERIFICABLE' => YELLOW }[status.to_s] || GRAY
  end

  def anatomy_names
    @anatomy_names ||= @result.account.jabvox_audio_anatomy_criteria.pluck(:id, :name).to_h
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
