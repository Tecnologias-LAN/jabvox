# WhatsApp Groups report actions for the v2 reports controller (Informes),
# kept in a concern so the controller stays a thin dispatcher. Admin-gated by the
# controller's check_authorization.
module Api::V2::Accounts::WhatsappGroupsReport
  extend ActiveSupport::Concern

  def whatsapp_groups_summary
    render json: whatsapp_groups_builder.summary
  end

  def whatsapp_groups_list
    render json: whatsapp_groups_builder.groups
  end

  private

  def whatsapp_groups_builder
    @whatsapp_groups_builder ||= V2::Reports::WhatsappGroupsReportBuilder.new(
      account: Current.account, params: whatsapp_groups_report_params
    )
  end

  def whatsapp_groups_report_params
    params.permit(:from, :to, :inbox_id)
  end
end
