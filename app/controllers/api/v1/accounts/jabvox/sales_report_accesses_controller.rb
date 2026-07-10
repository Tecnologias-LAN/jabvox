class Api::V1::Accounts::Jabvox::SalesReportAccessesController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_products'
  include JabvoxPermissions

  before_action :check_authorization, except: [:me]
  before_action :ensure_module_permission, except: [:me]

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

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    jabvox_authorize!('jabvox_sales_reports_manage')
  end

  def check_authorization
    authorize :jabvox_sales_report_access
  end
end
