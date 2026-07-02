class JabvoxTaxRatePolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_products_manage') || false
  end

  def index?   = @account_user.administrator? || @account_user.agent?
  def show?    = @account_user.administrator? || @account_user.agent?
  def create?  = can_manage?
  def update?  = can_manage?
  def destroy? = can_manage?

  class Scope < Scope
    def resolve = scope.all
  end
end
