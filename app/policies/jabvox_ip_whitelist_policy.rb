class JabvoxIpWhitelistPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_ip_whitelist_manage') || false
  end

  def index?   = can_manage?
  def show?    = can_manage?
  def create?  = can_manage?
  def update?  = can_manage?
  def destroy? = can_manage?

  class Scope < Scope
    def resolve = scope.all
  end
end
