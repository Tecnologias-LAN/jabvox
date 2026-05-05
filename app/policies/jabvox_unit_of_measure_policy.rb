class JabvoxUnitOfMeasurePolicy < ApplicationPolicy
  def index?   = @account_user.administrator? || @account_user.agent?
  def show?    = @account_user.administrator? || @account_user.agent?
  def create?  = @account_user.administrator?
  def update?  = @account_user.administrator?
  def destroy? = @account_user.administrator?

  class Scope < Scope
    def resolve = scope.all
  end
end
