# WhatsApp per-agent report: actions, param whitelisting and CSV/XLSX export,
# kept out of the controller so it stays a thin dispatcher.
module Api::V2::Accounts::WhatsappReportExporter
  extend ActiveSupport::Concern

  XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze
  EXPORT_HEADERS = ['Agente', 'Correo', 'Asignadas', 'Atendidas', 'Resueltas', 'Sin responder',
                    'Enviados', 'Recibidos', 'Entregados', 'Leídos', 'Fallidos', 'Tasa lectura %',
                    '1a respuesta (mediana s)', 'Resolución (mediana s)', 'SLA %', 'CSAT'].freeze
  BUSINESS_FILTER_KEYS = %i[q email phone document country campaign_id sold affiliate_id
                            inbox_id assignee_id team_id status management_state date_from date_to].freeze

  def whatsapp_agents
    render json: whatsapp_builder.agents
  end

  def whatsapp_summary
    render json: whatsapp_builder.summary
  end

  def whatsapp_rankings
    render json: whatsapp_builder.rankings(
      metric: params[:metric] || 'first_response', order: params[:order] || 'desc'
    )
  end

  def whatsapp_timeline
    render json: whatsapp_builder.conversation_timeline(params[:conversation_id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def whatsapp_label_durations
    render json: whatsapp_builder.label_durations
  end

  # Lista de plantillas usadas en masivos, para el desplegable del filtro.
  def whatsapp_templates
    render json: whatsapp_builder.template_names
  end

  # Lista de bandejas de WhatsApp, para el desplegable del filtro por bandeja.
  def whatsapp_inboxes
    render json: whatsapp_builder.whatsapp_inboxes
  end

  # Detalle por agente: mensajes con contacto, estado y error. Filtro opcional
  # por estado (?status=failed) para ver solo los fallidos, etc.
  def whatsapp_agent_detail
    uid = params[:agent_id].to_i
    render json: {
      summary: whatsapp_builder.agent_status_summary(uid),
      messages: whatsapp_builder.agent_messages(uid, status_filter: params[:msg_status])
    }
  end

  def whatsapp_export
    rows = whatsapp_builder.agents
    if params[:format].to_s == 'xlsx'
      send_data whatsapp_agents_xlsx(rows), type: XLSX_MIME,
                                            filename: 'whatsapp_agents.xlsx', disposition: 'attachment'
    else
      response.headers['Content-Type'] = 'text/csv'
      response.headers['Content-Disposition'] = 'attachment; filename=whatsapp_agents.csv'
      render plain: whatsapp_agents_csv(rows)
    end
  end

  private

  def whatsapp_builder
    @whatsapp_builder ||= V2::Reports::WhatsappAgentReportBuilder.new(
      account: Current.account, params: whatsapp_report_params
    )
  end

  def whatsapp_report_params
    params.permit(
      :from, :to, :inbox_id, :team_id, :status, :priority, :business_hours,
      :sla_seconds, :batch_uuid, :template_name, :sort_by, :order, :metric,
      agent_ids: [], labels: [], business: BUSINESS_FILTER_KEYS
    )
  end

  def whatsapp_export_row(row)
    [row[:name], row[:email], row[:conversations_assigned], row[:conversations_handled],
     row[:conversations_resolved], row[:no_reply], row[:sent], row[:received], row[:delivered],
     row[:read], row[:failed], row[:read_rate], row.dig(:first_response, :median),
     row.dig(:resolution, :median), row[:sla_pct], row[:csat_avg]]
  end

  def whatsapp_agents_csv(rows)
    require 'csv'
    CSV.generate(headers: true) do |csv|
      csv << EXPORT_HEADERS
      rows.each { |r| csv << whatsapp_export_row(r) }
    end
  end

  def whatsapp_agents_xlsx(rows)
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: 'WhatsApp por agente') do |sheet|
      sheet.add_row EXPORT_HEADERS
      rows.each { |r| sheet.add_row whatsapp_export_row(r) }
    end
    package.to_stream.read
  end
end
