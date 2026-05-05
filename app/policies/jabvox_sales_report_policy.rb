class JabvoxSalesReportPolicy < ApplicationPolicy
  def show?
    return true if @account_user.administrator?

    @account.jabvox_sales_report_accesses.exists?(user_id: @user.id, can_view_reports_jabvox: true)
  end

  def access?
    show?
  end
end
