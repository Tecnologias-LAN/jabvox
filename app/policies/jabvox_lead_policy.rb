class JabvoxLeadPolicy < ApplicationPolicy
  def index? = @account_user.administrator? || @account_user.agent?

  class Scope < Scope
    def resolve = scope.all
  end
end
