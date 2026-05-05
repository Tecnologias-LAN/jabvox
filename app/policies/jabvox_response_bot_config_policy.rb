class JabvoxResponseBotConfigPolicy < ApplicationPolicy
  def index?        = @account_user.administrator?
  def create?       = @account_user.administrator?
  def update?       = @account_user.administrator?
  def destroy?      = @account_user.administrator?
  def setup_labels? = @account_user.administrator?
end
