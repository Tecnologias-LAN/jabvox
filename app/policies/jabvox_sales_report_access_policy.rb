class JabvoxSalesReportAccessPolicy < ApplicationPolicy
  def index?  = @account_user.administrator?
  def update? = @account_user.administrator?
end
