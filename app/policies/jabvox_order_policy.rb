class JabvoxOrderPolicy < ApplicationPolicy
  def index?   = @account_user.administrator? || @account_user.agent?
  def show?    = @account_user.administrator? || @account_user.agent?
  def create?  = @account_user.administrator? || @account_user.agent?
  def update?  = @account_user.administrator? || @account_user.agent?
  def destroy? = @account_user.administrator?

  class Scope < Scope
    def resolve = scope.all
  end
end
