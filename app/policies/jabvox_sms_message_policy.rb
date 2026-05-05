class JabvoxSmsMessagePolicy < ApplicationPolicy
  def index? = @account_user.administrator?
  def stats? = @account_user.administrator?
end
