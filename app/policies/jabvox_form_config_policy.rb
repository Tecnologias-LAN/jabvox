class JabvoxFormConfigPolicy < ApplicationPolicy
  def show?          = @account_user.administrator?
  def update?        = @account_user.administrator?
  def provision_ssl? = @account_user.administrator?
end
