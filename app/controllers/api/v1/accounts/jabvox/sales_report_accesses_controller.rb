class Api::V1::Accounts::Jabvox::SalesReportAccessesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :check_authorization, except: [:me]

  def index
    @accesses = Current.account.jabvox_sales_report_accesses.includes(:user)
  end

  def update
    @access = Current.account.jabvox_sales_report_accesses.find_or_initialize_by(user_id: params[:id])
    @access.update!(can_view_reports_jabvox: params[:can_view_reports])
    render json: { id: @access.id, user_id: @access.user_id, can_view_reports: @access.can_view_reports_jabvox }
  end

  def me
    can_view = Current.account.jabvox_sales_report_accesses
                             .exists?(user_id: current_user.id, can_view_reports_jabvox: true)
    render json: { can_view: can_view }
  end

  private

  def check_authorization
    authorize :jabvox_sales_report_access
  end
end
