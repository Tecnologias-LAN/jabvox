class JabvoxSalesReportPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_sales_reports_manage') || false
  end

  def show?
    return true if can_manage?

    @account.jabvox_sales_report_accesses.exists?(user_id: @user.id, can_view_reports_jabvox: true)
  end

  def access?
    show?
  end
end
