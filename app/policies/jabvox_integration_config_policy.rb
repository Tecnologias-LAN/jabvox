class JabvoxIntegrationConfigPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_integration_manage') || false
  end

  def show?   = can_manage?
  def update? = can_manage?
end
