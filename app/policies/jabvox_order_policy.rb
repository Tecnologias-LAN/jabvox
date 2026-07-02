class JabvoxOrderPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_orders_manage') || false
  end

  def index?   = @account_user.administrator? || @account_user.agent?
  def show?    = @account_user.administrator? || @account_user.agent?
  def create?  = @account_user.administrator? || @account_user.agent?
  def update?  = @account_user.administrator? || @account_user.agent?
  def destroy? = can_manage?

  class Scope < Scope
    def resolve = scope.all
  end
end
