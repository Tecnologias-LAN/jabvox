class JabvoxIntegrationConfigPolicy < ApplicationPolicy
  def show?   = @account_user.administrator?
  def update? = @account_user.administrator?
end
