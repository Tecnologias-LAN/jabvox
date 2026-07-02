class JabvoxSalesReportAccessPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_sales_reports_manage') || false
  end

  def index?  = can_manage?
  def update? = can_manage?
end
