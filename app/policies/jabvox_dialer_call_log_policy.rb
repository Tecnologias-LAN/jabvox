class JabvoxDialerCallLogPolicy < ApplicationPolicy
  def index?  = @account_user.administrator? || @account_user.agent?
  def show?   = @account_user.administrator? || @account_user.agent?
  def create? = @account_user.administrator? || @account_user.agent?
  # Cualquier agente que atiende llamadas del dialer puede tipificarlas.
  # Sin este método el endpoint respondía 500 y la tipificación se perdía.
  def typify? = @account_user.administrator? || @account_user.agent?

  class Scope < Scope
    def resolve = scope.all
  end
end
