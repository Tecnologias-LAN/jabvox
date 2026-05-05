class JabvoxDialerCallLogPolicy < ApplicationPolicy
  def index? = @account_user.administrator? || @account_user.agent?
  def show?  = @account_user.administrator? || @account_user.agent?

  class Scope < Scope
    def resolve = scope.all
  end
end
